
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
# node :tmp1. Note, that in our example `tmp = x1 * x2`.
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



@runonce type ExNode{H}
    name::Symbol                   # name of a variable
    ex::Any                        # simple expression that produces `name`
    val::Any                       # value if any (e.g. for consts)
end

to_expr(node::ExNode) = node.ex

@runonce type ExGraph
    tape::Vector{ExNode}           # list of ExNode's
    idx::Dict{Symbol, ExNode}      # map from var name to its node in the graph
    input::Dict{Symbol,Any}        # input variables and their initializers
    expanded::Dict{Symbol,Any}     # expanded expressions that produce var
    mod::Module                    # module to evaluate expressions in
    last_id::Int                   # helper, index of last generated var name
end

function ExGraph(;mod=nothing, input...)
    mod = mod == nothing ? current_module() : mod
    g = ExGraph(ExNode[], Dict(), Dict(), Dict(), mod, 0)
    for (name, val) in input
        addnode!(g, name, Expr(:input, name), val)
    end
    return g
end

function Base.show(io::IO, g::ExGraph)
    print(io, "ExGraph\n")
    for node in g.tape
        print(io, "  $node\n")
    end
end

"""Generate new unique name for intermediate variable in graph"""
function genname(g::ExGraph)
    # TODO: check that it doesn't have collisions with input variables
    g.last_id += 1
    return Symbol("tmp$(g.last_id)")
end


## deps

"""Get symbols of dependenices of this node"""
deps(node::ExNode{:input}) = Symbol[]
deps(node::ExNode{:constant}) = Symbol[]
deps(node::ExNode{:(=)}) = [node.ex.args[2]]
deps(node::ExNode{:call}) = node.ex.args[2:end]


## special expressions

constant(x) = Expr(:constant, x)
input(x, val) = Expr(:input, x, val)


## expand expressions

"""
Expand expression, substituting all temporary vatiables by corresponding
expressions and all constants by their values.
"""
expand_expr(expanded::Dict{Symbol,Any}, ex::Expr) =
    expand_expr(expanded, to_exh(ex))

expand_expr(expanded::Dict{Symbol,Any}, ex) = ex
expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:input}) = exh.args[1]
expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:constant}) = exh.args[1]

function expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:(=)})
    return expanded[exh.args[2]]
end

function expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:call})
    op = exh.args[1]
    expd_args = [expand_expr(expanded, arg) for arg in exh.args[2:end]]
    new_ex = Expr(:call, op, expd_args...)
    return subs(new_ex, expanded)
end


## addnode!

"""
Add new node to the graph.
NOTE: `ex` should be SIMPLE expression already!
"""
function addnode!(g::ExGraph, name::Symbol, ex::Symbolic, val::Any)    
    node = ExNode{ex.head}(name, ex, val)
    push!(g.tape, node)
    g.idx[name] = node
    g.expanded[name] = expand_expr(g.expanded, ex)
    return name
end


## parse!

"""
Parse Julia expression and build ExGraph in-place.
Return the name of the output variable.
"""
parse!(g::ExGraph, ex::Expr) = parse!(g, to_exh(ex))
parse!(g::ExGraph, ::LineNumberNode) = :nil
parse!(g::ExGraph, s::Symbol) = s
parse!(g::ExGraph, ref::GlobalRef) = ref

function parse!(g::ExGraph, x::Number)
    name = addnode!(g, genname(g), constant(x), x)
    return name
end

function parse!(g::ExGraph, x::AbstractArray)
    name = addnode!(g, genname(g), constant(x), x)
    return name
end


function parse!(g::ExGraph, ex::ExH{:(=)})
    op = :(=)
    lhs, rhs = ex.args
    name = lhs
    dep = parse!(g, rhs)
    addnode!(g, name, :($name = $dep), nothing)
    return name
end


function parse!(g::ExGraph, ex::ExH{:call})    
    op = canonical(g.mod, ex.args[1])
    deps = Symbol[parse!(g, arg) for arg in ex.args[2:end]]
    name = addnode!(g, genname(g), Expr(:call, op, deps...), nothing)
    return name
end

function parse!(g::ExGraph, ex::ExH{:block})
    names = Symbol[parse!(g, subex) for subex in ex.args]
    return names[end]
end

function parse!(g::ExGraph, ex::ExH{:body})
    names = Symbol[parse!(g, subex) for subex in ex.args]
    return names[end]
end


## evaluate!

"""
Evaluate node, i.e. fill its `val` by evaluating node's expression w.r.t.
values of its dependencies.
"""
evaluate!(g::ExGraph, node::ExNode{:constant}) = node.val
evaluate!(g::ExGraph, node::ExNode{:input}) = node.val

function evaluate!(g::ExGraph, node::ExNode{:(=)})
    if (node.val != nothing) return node.val end
    dep_node = g.idx[deps(node)[1]]
    node.val = evaluate!(g, dep_node)
    return node.val
end

# consider all other cases as function calls
function evaluate!(g::ExGraph, node::ExNode{:call})
    if (node.val != nothing) return node.val end
    # TODO: dep may be a global constant (like π)
    dep_nodes = [g.idx[dep] for dep in deps(node)]
    # why this short version doesn't work?
    # dep_vals = [evaluate!(g, dep_node) for dep_node in dep_nodes]
    for dep_node in dep_nodes
        evaluate!(g, dep_node)
    end
    op = node.ex.args[1]
    dep_vals = [dep_node.val for dep_node in dep_nodes]
    ex = :(($op)($(dep_vals...)))
    node.val = eval(ex)
    return node.val
end

evaluate!(g::ExGraph, name::Symbol) = evaluate!(g, g.idx[name])


## forward pass

"""Forward pass of differentiation"""
function forward_pass(g::ExGraph, ex::Any)
    parse!(g, ex)
    evaluate!(g, g.tape[end].name)
    return g
end

## ## constant substitution
## function constants(g::ExGraph)
##     d = Dict{Symbol, Any}()
##     for node in g.tape
##         if node.op == :constant
##             d[node.name] = node.val
##         end
##     end
##     return d
## end

## """
## Substitute all constants in adjoint dict with their corresponding values
## """
## function subs_constants!(adj::Dict{Symbol,Any}, st::Dict{Symbol,Any})
##     st = constants(g)
##     for i in eachindex(g.adj)
##         g.adj[i] = subs(g.adj[i], st)
##     end
## end


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
function rev_step!(g::ExGraph, node::ExNode{:(=)}, adj::Dict{Symbol,Any})
    y = node.name
    x = deps(node)[1]
    adj[x] = adj[y]
end

function rev_step!(g::ExGraph, node::ExNode{:constant}, adj::Dict{Symbol,Any})
    adj[node.name] = 0.
end

function rev_step!(g::ExGraph, node::ExNode{:input}, adj::Dict{Symbol,Any})
    # do nothing
end

function rev_step!(g::ExGraph, node::ExNode{:call}, adj::Dict{Symbol,Any})
    y = node.name
    types = [typeof(g.idx[x].val) for x in deps(node)]
    for (i, x) in enumerate(deps(node))
        x_node = g.idx[x]
        op = opname(g.mod, node.ex.args[1])
        maybe_rule = find_rule(op, types, i)        
        rule = !isnull(maybe_rule) ? get(maybe_rule) : register_rule(op, types, i)
        dydx = apply_rule(rule, to_expr(node))
        dzdy = adj[y]
        a = simplify(dzdy * dydx)
        if haskey(adj, x)
            adj[x] += a
        else
            adj[x] = a
        end
    end
end


## reverse pass

function reverse_recursive!(g::ExGraph, curr::Symbol, adj::Dict{Symbol, Any})
    node = g.idx[curr]
    rev_step!(g, node, adj)
    for dep in deps(node)
        reverse_recursive!(g, dep, adj)
    end
end

"""Reverse pass of differentiation"""
function reverse_pass(g::ExGraph, output::Symbol)
    adj = Dict{Symbol,Any}()
    adj[output] = 1.
    reverse_recursive!(g, output, adj)
    eadj = similar(adj)
    for (name, dex) in adj
        expanded = subs(dex, g.expanded)
        eadj[name] = simplify(expanded)
    end
    return eadj
end


function _rdiff(ex::Expr; xs...)
    mod = current_module()
    g = ExGraph(;mod=mod, xs...)
    forward_pass(g, ex)
    output = g.tape[end].name
    adj = reverse_pass(g, output)
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
