
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
    g = ExGraph(ExNode[], Dict(), Dict(), Dict(), 0)
    for (name, val) in input
        addnode!(g, name, Expr(:input, name), val)
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


## deps

deps(node::ExNode{:input}) = Symbol[]
deps(node::ExNode{:constant}) = Symbol[]
deps(node::ExNode{:(=)}) = [node.ex.args[2]]
deps(node::ExNode{:call}) = node.ex.args[2:end]


## special expressions

constant(x) = Expr(:constant, x)
input(x, val) = Expr(:input, x, val)


## expand expressions

expand_expr(expanded::Dict{Symbol,Any}, ex::Expr) =
    expand_expr(expanded, to_exh(ex))

expand_expr(expanded::Dict{Symbol,Any}, ex) = ex
expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:input}) = exh.args[1]
expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:constant}) = exh.args[1]

function expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:(=)})
    return expand_expr(expanded, exh.args[2])
end

function expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:call})
    op = exh.args[1]
    expd_args = [expand_expr(expanded, arg) for arg in exh.args[2:end]]
    new_ex = Expr(:call, op, expd_args...)
    return subs(new_ex, expanded)
end




## addnode!


# NOTE: `ex` should be SIMPLE expression already! 
function addnode!(g::ExGraph, name::Symbol, ex::Symbolic, val::Any)
    node = ExNode{ex.head}(name, ex, val)
    push!(g.tape, node)
    g.idx[name] = node
    # g.expanded[name] = subs(ex, g.expanded)
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


## evaluate!

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

function forward_pass(g::ExGraph, ex::Any)
    parse!(g, ex)
    evaluate!(g, g.tape[end].name)
    return g
end


## reverse step

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
        op = node.ex.args[1]
        rule = find_rule(op, types, i)
        dydx = apply_rule(rule, to_expr(node))        
        dzdy = adj[y]
        a = simplify(dzdy * dydx)
        # a = dzdy * dydx
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

function reverse_pass(g::ExGraph, output::Symbol)
    adj = Dict{Symbol,Any}()
    adj[output] = 1.
    reverse_recursive!(g, output, adj)
    return adj
end

function reverse_pass(g::ExGraph, outputs::Vector{Symbol})
    derivs = Dict{Symbol, Any}()
    for output in outputs
        derivs[output] = reverse_pass(g, output)
    end
    return derivs
end


function _rdiff(ex::Expr; xs...)
    g = ExGraph(;xs...)
    forward_pass(g, ex)
    output = g.tape[end].name
    adj = reverse_pass(g, output)
    return g, adj
end

function rdiff(ex::Expr; xs...)
    g, adj = _rdiff(ex; xs...)
    names = [name for (name, val) in xs]
    derivs = [adj[name] for name in names]
    return derivs
end
    
