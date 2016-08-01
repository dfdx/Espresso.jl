
import Base: *, +

@runonce type ExH{H}
    head::Symbol
    args::Vector
    typ::Any
end

toExH(ex::Expr) = ExH{ex.head}(ex.head, ex.args, ex.typ)

@runonce type ExNode{Op}
    name::Symbol                # name of a variable
    op::Symbol                  # operation that produced it or special symbol
    deps::Vector{Symbol}        # dependencies of this variable (e.g. args of op)
    val::Any                    # value if any (e.g. for consts)
end

@runonce type ExGraph
    tape::Vector{ExNode}              # list of ExNode's
    vars::Dict{Symbol, ExNode}        # map from var name to its node in the graph
    input::Vector{Tuple{Symbol,Any}}  # list of input variables
    adj::Dict{Symbol,Any}             # dictionary of adjoints (derivatives)
    last_id::Int                      # helper, index of last generated var name
end

function ExGraph(;input...)
    g = ExGraph(ExNode[], Dict(), input, Dict(), 0)
    for (name, val) in input
        addnode!(g, :input; name=name, val=val)
    end
    return g
end

function ExGraph()
    return ExGraph(ExNode[], Dict(), [], Dict(), 0)
end

function Base.show(io::IO, g::ExGraph)
    print(io, "ExGraph\n")
    for node in g.tape
        print(io, "  $node\n")
    end
end

function genname(g::ExGraph)
    g.last_id += 1
    return symbol("w$(g.last_id)")
end


## addnode!

function addnode!(g::ExGraph, name::Symbol, op::Symbol,
                  deps::Vector{Symbol}, val::Any)
    node = ExNode{op}(name, op, deps, val)
    push!(g.tape, node)
    g.vars[name] = node
    return name
end

function addnode!(g::ExGraph, op::Symbol;
                  name=:generate, deps=Symbol[], val=nothing)
    name = (name == :generate ? genname(g) : name)
    return addnode!(g, name, op, deps, val)
end


## parse!

"""
Parse Julia expression and build ExGraph in-place.
Return the name of the output variable.
"""
parse!(g::ExGraph, ex::Expr) = parse!(g, toExH(ex))
parse!(g::ExGraph, ::LineNumberNode) = :nil
parse!(g::ExGraph, s::Symbol) = s

function parse!(g::ExGraph, x::Number)
    name = addnode!(g, :constant; val=x)
    return name
end


function parse!(g::ExGraph, ex::ExH{:(=)})
    op = :(=)
    rhs, lhs = ex.args
    name = rhs
    deps = [parse!(g, lhs)]
    addnode!(g, op; name=name, deps=deps)
    return name
end

function parse!(g::ExGraph, ex::ExH{:call})
    op = ex.args[1]
    # deps = flatten(Symbol, [parse!(g, arg) for arg in ex.args[2:end]])
    deps = Symbol[parse!(g, arg) for arg in ex.args[2:end]]
    name = addnode!(g, op; deps=deps)
    return name
end

function parse!(g::ExGraph, ex::ExH{:block})
    names = Symbol[parse!(g, subex) for subex in ex.args]
    return names[end]
end


## evaluate!

evaluate!(g::ExGraph, node::ExNode{:constant}) = node.val
evaluate!(g::ExGraph, node::ExNode{:input}) = node.val

function evaluate!(g::ExGraph, node::ExNode{:(=)})
    if (node.val != nothing) return node.val end
    dep_node = g.vars[node.deps[1]]
    node.val = evaluate!(g, dep_node)
    return node.val
end

# consider all other cases as function calls
function evaluate!{Op}(g::ExGraph, node::ExNode{Op})
    if (node.val != nothing) return node.val end
    dep_nodes = [g.vars[dep] for dep in node.deps]
    # why this short version doesn't work?
    # dep_vals = [evaluate!(g, dep_node) for dep_node in dep_nodes]
    for dep_node in dep_nodes
        evaluate!(g, dep_node)
    end
    dep_vals = [dep_node.val for dep_node in dep_nodes]
    ex = :(($Op)($(dep_vals...)))
    node.val = eval(ex)
    return node.val
end

evaluate!(g::ExGraph, name::Symbol) = evaluate!(g, g.vars[name])


# derivation

include("deriv_rules.jl")  # TODO: consider different location

## rdiff

function to_expr(node::ExNode)
    op = node.op
    ex = :(($op)($(node.deps...)))
    return ex
end

"""
Fill derivatives of dependencies of `y`.
`dzdy` is a current values of dz/dy and is equal to 1 for output var and
some expression for intermediate vars.
Naming:
 * z - output variable
 * y - variable at hand
 * x - one of y's dependencies
"""
function fill_deriv!(g::ExGraph, y::Symbol, dzdy::Any)
    y_node = g.vars[y]
    types = [typeof(g.vars[x].val) for x in y_node.deps]
    for (i, x) in enumerate(y_node.deps)
        x_node = g.vars[x]
        rule = getrule(y_node.op, types, i)
        dydx = applyrule(rule, to_expr(y_node))
        a = simplify(dzdy * dydx)
        if haskey(g.adj, x)
            g.adj[x] += a
        else
            g.adj[x] = a
        end
    end
    return g.adj  # for convenience, may become not-destructuring later
end

"""
Calculate derivatives of all direct and indirect dependencies of z,
store result in adjoint dict `g.adj`.
"""
function calc_deriv!(g::ExGraph, z::Symbol)
    fill_deriv!(g, z, 1)
    for dep in g.vars[z].deps
        calc_deriv!(g, dep)
    end
end


function constants(g::ExGraph)
    d = Dict{Symbol, Any}()
    for node in g.tape
        if node.op == :constant
            d[node.name] = node.val
        end
    end
    return d
end

"""
Substitute all constant node names in adjoint dict with
their corresponding values
"""
function subs_constants!(g::ExGraph)
    st = constants(g)
    for i in eachindex(g.adj)
        g.adj[i] = subs(g.adj[i], st)
    end
end


function rdiff(ex::Expr; output=nothing, inputs...)    
    g = ExGraph(;inputs...)
    parse!(g, ex)
    output = output != nothing ? output : g.tape[end].name
    evaluate!(g, output)
    calc_deriv!(g, output)
    subs_constants!(g)
    d_exprs = [simplify(g.adj[x]) for (x,val) in inputs]
    return d_exprs
end


################# main ###################

function main()
    # ex = :(z = x1*x2 + sin(x1))
    ex = :(z = x1 ^ 2)
    g = ExGraph(;x1=1., x2=2.)
    parse!(g, ex)
    evaluate!(g, :z)
    calc_deriv!(g, :z)
    subs_constants!(g)
end
