
# rdiff.jl - differentiate an expression or a function w.r.t. its arguments
#
# An approach taken in this file falls into a category of hybric method of
# computer-aided differentiation. General architecture closely follows
# reverse-mode automatic differentiation including building a "tape" and
# propagating derivative from an output to an input variables, but unlike AD
# it allows to output symbolic expressions for calculating partial derivatives
# in question.
#
# Advantages of this approach include efficient computation of derivatives
# (which may not always be a case for symbolic differentiation), outputting
# symbolic expression which only needs to be computed once at runtime
# (unlike full reverse-mode AD that requires 2 passes) and may be used to
# generate code for other systems like GPU (which is not possible with AD at all).
# The main disadvantage compared to AD is inability to handle conditions and
# loops since they create discontinuity and thus are very hard to analyze
# and produce symbolic expression.
#
#
# Architecture
# ------------
#
# Just as reverse-mode AD, we build derivative using 2 passes -
# forward and reverse.
#
# 1. During forward pass we parse expression and build a graph (`ExGraph`) -
#    "linearized" version of expression. Each node in this graph represents:
#
#     * function call: `ExNode{:call}`
#     * assignment: `ExNode{:(=)}`
#     * input variable: `ExNode{:input}`
#     * constant value: `ExNode{:constant}`
#
#    Nodes are created and put onto a "tape" (list of nodes) using `parse!()`
#    function in a topological order, so no node may refer to a dependency
#    that isn't defined yet. After the graph is built, all nodes are evaluated
#    using input variables and constants to provide "example values" for each
#    node (used for type inference and other stuff).
#
# 2. Reverse pass starts with an empty dict of "adjoints" - derivatives of
#    an output variable w.r.t. to current variable - and populating it
#    from the end to the beginning (or, more precisely, from dependent variables
#    to their dependencies).
#
#    The backbone of this process is `rev_step!` function, and the most
#    intersting method is the one that handles function call. Given a node
#    and a dict of all dependent adjoints, this method does the following
#    for each of its dependencies (here `z` stands for an output variable,
#    `y` - for current variable and `x` - for current dependency of `y`):
#
#     1) finds a differentiation rule for `dy/dx`, i.e. derivative of current
#        node w.r.t. current dependency
#     2) symbolically multiplies it by `dz/dy`, i.e. by derivative of output
#        variable w.r.t. current node, to obtain `dz/dx`, i.e. derivative of
#        output w.r.t. curent dependency
#     3) adds this new derivative to the adjoint dict
#
#
# Example
# -------
#
# Here's an example of this process (and some tips on how to debug it).
#
# Suppose we have expression:
#
#     ex = :(z = x1*x2 + sin(x1))
#
# We can build an `ExGraph` and perform forward pass on it like this (which is
# not necessary for high-level usage, but helpful for debugging):
#
#     g = ExGraph(;x1=1, x2=1)  # give it an example of possible values
#     forward_pass(g, ex)
#
# After this our graph looks like:
#
#   ExGraph
#     ExNode{:input}(:x1,:($(Expr(:input, :x1))),1)
#     ExNode{:input}(:x2,:($(Expr(:input, :x2))),1)
#     ExNode{:call}(:tmp1,:(x1 * x2),1)
#     ExNode{:call}(:tmp2,:(sin(x1)),0.8414709848078965)
#     ExNode{:call}(:tmp3,:(tmp1 + tmp2),1.8414709848078965)
#     ExNode{:(=)}(:z,:(z = tmp3),1.8414709848078965)
#
# Let's take a node with a first call for example:
#
#   ExNode{:call}(:tmp1,:(x1 * x2),1)
#
# Here `ExNode` is parametrized by :call symbol to enable Julia's fancy method
# dispatching, :tmp1 is a name of a new variable which is a product of variables
# :x1 and :x2 and has example value of 1.
#
# Now let's run reverse pass to obtain derivatives of `z` w.r.t. all other vars:
#
#     adj = reverse_pass(g, :z)
#
# which results in a dict like this:
#
#     Dict{Symbol,Any} with 6 entries:
#        :tmp2 => 1.0
#        :x1   => :(x2 + cos(x1))
#        :z    => 1.0
#        :tmp1 => 1.0
#        :x2   => :x1
#        :tmp3 => 1.0
#
# This means that:
#
#     dz/dz == adj[:z] == 1.0
#     dz/dtmp3 == adj[:tmp3] == 1.0
#     dz/dx1 == adj[:x1] == :(x2 + cos(x1))
#     ...
#
# To see how it works, consider finding derivative `dz/dx1` at intermediate
# node :tmp1. Note, that in our example `tmp1 = x1 * x2`.
#
# 1) by the time of computing this derivative we already know that
#    `dz/dtmp1 == 1.0`
# 2) from primitive derivative rules for product of numbers we also infer that
#    `dtmp1/dx1 == x2`
# 3) using chain rule we obtain (part of*) `dz/dx1` as a symbolic product
#    `dz/dmp1 * dtmp1/dx1 == 1.0 * x2 == x2`.
#
# I say "part of" because :z depends on :x1 not only through :tmp1, but also
# through :tmp2, for which derivative `dz/dx1` turns to be `cos(x1)`.
# To combine 2 these "parts" we simply add them up and obtain final result:
#
#     dz/dx1 == x2 + cos(x1)
#
# (NOTE: if you have any reference why these "parts" of derivative should be
# summed, who introduced this rule or how it is inferred, please open an
# issue or PR in this repository on GitHub).



## forward pass

"""Forward pass of differentiation"""
function forward_pass(g::ExGraph, ex::Any)
    parse!(g, ex)
    evaluate!(g, g.tape[end].var)
    return g
end


## register rule

"""
Register new differentiation rule for function `fname` with arguments
of `types` at index `idx`, return this new rule.
"""
function register_rule(fname::OpName, types::Vector{DataType}, idx::Int)
    f = eval(fname)
    args, ex = funexpr(f, types)
    ex = sanitize(ex)
    # TODO: replace `ones()` with `example_val()` that can handle arrays
    xs = [(arg, ones(T)[1]) for (arg, T) in zip(args, types)]
    derivs = rdiff(ex; xs...)
    dex = derivs[idx]
    fex = Expr(:call, fname, args...)
    # TODO: use @diff_rule instead for more flexibility
    DIFF_RULES[(fname, types, idx)] = (fex, dex)
    return (fex, dex)
end



## reverse step

"""
Perform one step of reverse pass. Add derivatives of output variable w.r.t.
node's dependenices to adjoint dictionary.
"""
function rev_step!(g::ExGraph, nd::ExNode{:(=)}, adj::Dict{Symbol, TensorDeriv})
    # TODO: detect index permutation or inner contraction and handle it properly
    y = nd.var
    x = dependencies(nd)[1]
    dzdx = copy(adj[y])
    dzdx.wrt.args[1] = dname(x)
    adj[x] = dzdx
end

function rev_step!(g::ExGraph, nd::ExNode{:constant},
                   adj::Dict{Symbol, TensorDeriv})
    adj[nd.var] = 0.
end

function rev_step!(g::ExGraph, node::ExNode{:input},
                   adj::Dict{Symbol,TensorDeriv})
    # do nothing ??
end



## function rev_step!(g::ExGraph, dg::ExGraph, nd::ExNode{:call})
##     y = nd.var
##     types = DataType[typeof(value(get(g, x))) for x in dependencies(nd)]
##     for (i, x) in enumerate(dependencies(nd))
##         xnd = g[x]
##         op = opname(g.mod, nd.ex.args[1])
##         if isindexed(nd)  # indexed expression
##             elem_types = map(eltype, types)
##             maybe_rule = find_rule(op, elem_types, i)
##             if !isnull(maybe_rule)
##                 rule = get(maybe_rule)
##                 dydx = apply_rule(rule, expr(nd))
##                 dzdy = expr(dg[dname(y)])
##                 # TODO: add indices from original expression
##                 if haskey(dg, x)
##                     dzdx_nd = dg[x]
##                     dzdx_nd.ex += dzdy * dydx  # FIXME: not simple expression!
##                 else
##                     addnode!(dg, :call, dname(x), dzdy * dydx)
##                 end
##             end  # TODO: otherwise try register or fail
##         else # non-indexed expression
##             maybe_rule = find_rule(op, types, i)
##             if !isnull(maybe_rule)
##                 rule = get(maybe_rule)
##                 dydx = apply_rule(rule, expr(nd))
##                 dzdy = expr(dg[dname(y)])
##                 if haskey(dg, x)
##                     dzdx_nd = dg[x]
##                     dzdx_nd.ex += dzdy * dydx
##                 else
##                     addnode!(dg, :call, dname(x), dzdy * dydx)
##                 end
##             end
##             # TODO: try to convert to indexed and find rule for components
##             #       expression then stays vectorized,
##             #       but derivative becomes indexed
##             # TODO: if nothing works, try to register new rule
##         end
##     end
## end


function rev_step!(g::ExGraph, nd::ExNode{:call}, adj::Dict{Symbol, TensorDeriv})
    y = nd.var
    iex = to_iexpr(nd)
    dzdy = adj[y]
    for (i, x) in enumerate(dependencies(nd))
        dydx = tderivative(iex, x)
        dzdx = dzdy * dydx
        if haskey(adj, x)
            adj[x] += dzdx
        else
            adj[x] = dzdy * dydx
        end
    end
end



## reverse pass

## function reverse_recursive!(g::ExGraph, curr::Symbol, adj::Dict{Symbol, Any})
##     node = g.idx[curr]
##     rev_step!(g, node, adj)
##     for dep in dependencies(node)
##         reverse_recursive!(g, dep, adj)
##     end
## end

"""Reverse pass of differentiation"""
function reverse_pass(g::ExGraph, z::Symbol)
    num_indices = ndims(g[z].val)
    dz = with_indices(dname(z), num_indices)
    dzwrt = with_indices(dname(z), num_indices+1, num_indices)
    guards = [:($ivar == $iwrt)
              for (ivar, iwrt) in zip(dz.args[2:end], dzwrt.args[2:end])]
    # later: check if g has indexed expressions and if not,
    # use Dict{Symbol, Deriv} instead to call other rev_step! methods
    adj = Dict(z => TensorDeriv(dz, dzwrt, 1, guards))
    for nd in reverse(g.tape)
        rev_step!(g, nd, adj)
    end
    return adj
end


function _rdiff(ex::Expr; xs...)
    mod = current_module()
    g = ExGraph(;mod=mod, xs...)
    forward_pass(g, ex)
    z = g.tape[end].var
    adj = reverse_pass(g, z)
    return g, adj
end

"""
rdiff(ex::Expr; xs...)

Differentiate expression `ex` w.r.t. variables `xs`. `xs` should be a list
of key-value pairs with keys representing variables in expression and values
representing 'example values' (used e.g. for type inference). Returns an array
of symbolic expressions representing derivatives of ex w.r.t. each of passed
variabels. Example:

    rdiff(:(x^n), x=1, n=1)
    # ==> [:(n * x ^ (n - 1))  -- derivative w.r.t. :x
    #      :(log(x) * x ^ n)]  -- derivative w.r.t. :n
"""
function rdiff(ex::Expr; xs...)
    g, adj = _rdiff(ex; xs...)
    names = [name for (name, val) in xs]
    derivs = [adj[name] for name in names]
    return derivs
end

"""
rdiff(f::Function, xs...)

Differentiate function `f` w.r.t. its argument. See `rdiff(ex::Expr, xs...)`
for more details.
"""
function rdiff(f::Function; xs...)
    types = [typeof(x[2]) for x in xs]
    args, ex = funexpr(f, types)
    ex = sanitize(ex)
    # TODO: map xs to args
    derivs = rdiff(ex; xs...)
end



# TODO: elementwise functions


function main()
    ex = quote
        D[i,j] = A[i,k] * B[k,j] + C[i,j]
    end
    # ex = :(A[i,k] * B[k,j])
    # ex = :(B[i,j] = A[j,i])
    A = rand(2, 3)
    B = rand(3, 2)
    C = rand(2, 2)
    tds = rdiff(ex, A=A, B=B, C=C)
end
