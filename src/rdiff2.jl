
@runonce type ExH{H}
    head::Symbol
    args::Vector
    typ::Any
end

to_exh(ex::Expr) = ExH{ex.head}(ex.head, ex.args, ex.typ)


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
    last_id::Int                   # helper, index of last generated var name
end

function ExGraph(;input...)
    g = ExGraph(ExNode[], Dict(), input, Dict(), Dict(), 0)
    for (name, val) in input
        addnode!(g, :input; name=name, val=val)
    end
    return g
end

function ExGraph()
    return ExGraph(ExNode[], Dict(), Dict(), Dict(), 0)
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


## special expressions

constant(x) = Expr(:constant, x)
input(x, val) = Expr(:input, x, val)


## addnode!

# to_node(ex::Expr) = ExNode{ex.head}(name, ex, val)   # needed?

# NOTE: `ex` should be SIMPLE expression already! 
function addnode!(g::ExGraph, name::Symbol, ex::Symbolic, val::Any)
    node = ExNode{ex.head}(name, ex, val)
    push!(g.tape, node)
    g.idx[name] = node
    g.expanded[name] = subs(ex, g.expanded)
    return name
end

# function addnode!(g::ExGraph, ex::Expr)
#     name = genname(g)
#     return addnode!(g, name, ex, nothing)
# end


## parse!

"""
Parse Julia expression and build ExGraph in-place.
Return the name of the output variable.
"""
parse!(g::ExGraph, ex::Expr) = parse!(g, to_exh(ex))
parse!(g::ExGraph, ::LineNumberNode) = :nil
parse!(g::ExGraph, s::Symbol) = s

function parse!(g::ExGraph, x::Number)
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
    op = ex.args[1]
    deps = Symbol[parse!(g, arg) for arg in ex.args[2:end]]
    name = addnode!(g, genname(g), Expr(:call, op, deps...), nothing)
    return name
end

function parse!(g::ExGraph, ex::ExH{:block})
    names = Symbol[parse!(g, subex) for subex in ex.args]
    return names[end]
end
