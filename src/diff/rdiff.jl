
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
    evaluate!(g, g.tape[end].var)
    return g
end


## reverse step

"""
Perform one step of reverse pass. Add derivatives of output variable w.r.t.
node's dependenices to adjoint dictionary.
"""
function rev_step!(g::ExGraph, nd::ExNode{:(=)}, adj::Dict{Symbol,Deriv})
    y = nd.var
    x = dependencies(nd)[1]
    adj[x] = adj[y]
end

function rev_step!(g::ExGraph, nd::ExNode{:constant}, adj::Dict{Symbol,Deriv})
    adj[nd.var] = Deriv(0.)
end

function rev_step!(g::ExGraph, nd::ExNode{:input}, adj::Dict{Symbol,Deriv})
    # do nothing
end

function rev_step!(g::ExGraph, nd::ExNode{:call}, adj::Dict{Symbol,Deriv})
    y = nd.var
    types = [typeof(g.idx[x].val) for x in dependencies(nd)]
    for (i, x) in enumerate(dependencies(nd))
        xnd = g[x]
        dydx = derivative(expr(nd), types, i, mod=g.ctx[:mod])
        dzdy = adj[y]
        a = dzdy * dydx
        if haskey(adj, x)
            adj[x] += a
        else
            adj[x] = a
        end
    end
end


## reverse pass

function expand_adjoints(g::ExGraph, adj::Dict{Symbol, Deriv})
    return Dict([(var, simplify(expand_temp(g, expr(d)))) for (var, d) in adj])
end


"""Reverse pass of differentiation"""
function reverse_pass(g::ExGraph, z::Symbol)
    if any(isindexed, g.tape)
        num_indices = ndims(g[z].val)
        dz = with_indices(dname(z), num_indices)
        dzwrt = with_indices(dname(z), num_indices+1, num_indices)
        guards = [:($ivar == $iwrt)
                  for (ivar, iwrt) in zip(dz.args[2:end], dzwrt.args[2:end])]
        # later: check if g has indexed expressions and if not,
        # use Dict{Symbol, Deriv} instead to call other rev_step! methods
        adj = Dict(z => TensorDeriv(dz, dzwrt, 1., guards))
    else
        adj = Dict(z => Deriv(1.))
    end
    for nd in reverse(g.tape)
        rev_step!(g, nd, adj)
    end
    return adj
end


function _rdiff(ex::Expr; ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    g = ExGraph(ex; ctx=ctx, inputs...)
    forward_pass(g, ex)
    z = g.tape[end].var
    adj = reverse_pass(g, z)
    return g, expand_adjoints(g, adj)
end


"""
rdiff(ex::Expr; ctx=Dict(), xs...)

Differentiate expression `ex` w.r.t. variables `xs`. `xs` should be a list
of key-value pairs with keys representing variables in expression and values
representing 'example values' (used e.g. for type inference). Returns an array
of symbolic expressions representing derivatives of ex w.r.t. each of passed
variabels. Example:

    rdiff(:(x^n), x=1, n=1)
    # ==> Dict(:x => :(n * x ^ (n - 1)),  -- derivative w.r.t. :x
    #          :n => :(log(x) * x ^ n))   -- derivative w.r.t. :n

Options (passed via `ctx`):

  * :method - method to differentiate with (:vec or :ein)
  * :outfmt - output format (:vec or :ein)
"""
function rdiff(ex::Expr; ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    meth = @get(ctx, :method, any(x -> !isa(x[2], Number), inputs) ? :ein : :vec)
    ex_ = meth == :ein ? to_einstein(ex; inputs...) : ex
    g, adj = _rdiff(ex_; ctx=ctx, inputs...)
    vars = Set([var for (var, val) in inputs])
    dexs = Dict([(var, dex) for (var, dex) in adj if in(var, vars)])
    outfmt = @get(ctx, :outfmt, :vec)
    outdexs = (outfmt == :vec && meth == :ein ?
               Dict([(var, from_einstein(dex; inputs...))
                     for (var, dex) in dexs]) :
               dexs)
    return outdexs
end


function example_val{T}(::Type{T})
    if T <: Number
        return one(T)
    elseif T <: Array
        return ones(eltype(T), [1 for i=1:ndims(T)]...)
    else
        error("Don't know how to create example value for type $T")
    end
end


"""
rdiff(f::Function, xs...)

Differentiate function `f` w.r.t. its argument. See `rdiff(ex::Expr, xs...)`
for more details.
"""
function rdiff(f::Function, types::Vector{DataType}; ctx=Dict())
    ctx = to_context(ctx)
    args, ex = funexpr(f, types)
    vals = map(example_val, types)
    inputs = collect(zip(args, vals))
    ex = sanitize(ex)
    return rdiff(ex; ctx=ctx, inputs...)
end


function fdiff(f::Function, types::Vector{DataType}; ctx=Dict())
    # TODO
end


#-----------------------------------------------------------------


logistic(x) = 1 ./ (1 + exp(-x))

function main2()
    ex = :(sum(W * x + b))
    ctx = Dict()
    inputs = [:W=>rand(3,4), :x=>rand(4), :b=>rand(3)]
    ds = rdiff(ex; inputs...)

    ex = :(sum(logistic(W * x)))
    ds = rdiff(ex; inputs...)
    
    vex = :(sum(W))
    tex = to_einstein(vex; inputs...)
    g, adj = _rdiff(tex; inputs...)
end

