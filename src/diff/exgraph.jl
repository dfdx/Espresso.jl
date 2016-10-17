
# exgraph.jl - expression graph as a list of primitive expression nodes

# exnode

@runonce type ExNode{C}         # C - category of node, e.g. :call, :=, etc.
    var::Symbol                 # variable name
    ex::Any                     # simple expression that produces name
    idxs::Vector{Vector}        # indexes (var : args) if in Einstein notation
    val::Any                    # example value
end

ExNode(C::Symbol, var::Symbol, ex::Any) = ExNode{C}(var, ex, [], nothing)

# category{C}(nd::ExNode{C}) = C
variable(nd::ExNode) = nd.var
value(nd::ExNode) = nd.val
expr(nd::ExNode) = nd.ex
function iexpr(nd::ExNode)
    varex = Expr(:ref, nd.var, nd.idxs[1]...)
    s2i = Dict([(dep, idxs)
                for (dep, idxs) in zip(dependencies(nd), nd.idxs[2:end])])
    depex = add_indices(nd.ex, s2i)
    return depex
end


## deps

"""Get symbols of dependenices of this node"""
dependencies(nd::ExNode{:input}) = Symbol[]
dependencies(nd::ExNode{:constant}) = Symbol[]
dependencies(nd::ExNode{:(=)}) = [nd.ex]
dependencies(nd::ExNode{:call}) = nd.ex.args[2:end]

to_expr(nd::ExNode) = :($(nd.var) = $(nd.ex))
function to_einsum_expr(nd::ExNode)
    varex = Expr(:ref, nd.var, nd.idxs[1]...)
    s2i = Dict([(dep, idxs)
                for (dep, idxs) in zip(dependencies(nd), nd.idxs[2:end])])
    depex = add_indices(nd.ex, s2i)
    assign_ex = Expr(:(:=), varex, depex)
    return Expr(:macrocall, Symbol("@einsum"), assign_ex)
end

function to_iexpr(nd::ExNode)
    varex = Expr(:ref, nd.var, nd.idxs[1]...)
    s2i = Dict([(dep, idxs)
                for (dep, idxs) in zip(dependencies(nd), nd.idxs[2:end])])
    depex = add_indices(nd.ex, s2i)
    return Expr(:(=), varex, depex)
end

function Base.show{C}(io::IO, nd::ExNode{C})
    val = isa(nd.val, AbstractArray) ? "<$(typeof(nd.val))>" : nd.val
    print(io, "ExNode{$C}($(to_expr(nd)) | $val)")
end

isindexed(nd::ExNode) = !isempty(nd.idxs) && !isempty(nd.idxs[1])


# exgraph

@runonce type ExGraph
    tape::Vector{ExNode}           # list of ExNode's
    idx::Dict{Symbol, ExNode}      # map from var name to its node in the graph
    input::Dict{Symbol,Any}        # input variables and their initializers
    mod::Module                    # module to evaluate expressions in
    last_id::Int                   # helper, index of last generated var name
end

function ExGraph(;mod=nothing, input...)
    mod = mod == nothing ? current_module() : mod
    g = ExGraph(ExNode[], Dict(), Dict(), mod, 0)
    for (var, val) in input
        addnode!(g, :input, var, var; val=val)
    end
    return g
end

function Base.show(io::IO, g::ExGraph)
    print(io, "ExGraph\n")
    for node in g.tape
        print(io, "  $node\n")
    end
end

Base.haskey(g::ExGraph, var::Symbol) = haskey(g.idx, var)
Base.get(g::ExGraph, var::Symbol) = g.idx[var]
Base.getindex(g::ExGraph, var::Symbol) = g.idx[var]
Base.getindex(g::ExGraph, i::Integer) = g.tape[i]

"""Generate new unique name for intermediate variable in graph"""
function genname(g::ExGraph)
    # TODO: check that it doesn't have collisions with input variables
    g.last_id += 1
    return Symbol("tmp$(g.last_id)")
end


## addnode!

"""
Add new node to a graph. Expression should be simple, e.g.
nested calls or blocks are not allowed (use parse!() for it).
"""
function addnode!(g::ExGraph, C::Symbol, var::Symbol, ex::Any;
                  idxs=Vector[], val=nothing)
    nd = ExNode{C}(var, ex, idxs, val)
    push!(g.tape, nd)
    g.idx[var] = nd
    return var
end



## special expressions
    
## constant(val) = Expr(:constant, val)
## input(x, val) = Expr(:input, x, val)
## assign(x) = Expr(:(=), x)


## ## expand expressions

## """
## Expand expression, substituting all temporary vatiables by corresponding
## expressions and all constants by their values.
## """
## expand_expr(expanded::Dict{Symbol,Any}, ex::Expr) =
##     expand_expr(expanded, to_exh(ex))

## expand_expr(expanded::Dict{Symbol,Any}, ex) = ex
## expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:input}) = exh.args[1]
## expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:constant}) = exh.args[1]

## function expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:(=)})
##     return expanded[exh.args[2]]
## end

## function expand_expr(expanded::Dict{Symbol,Any}, exh::ExH{:call})
##     op = exh.args[1]
##     expd_args = [expand_expr(expanded, arg) for arg in exh.args[2:end]]
##     new_ex = Expr(:call, op, expd_args...)
##     return subs(new_ex, expanded)
## end

expand_temp(g::ExGraph, nd::ExNode{:input}) = variable(nd)
expand_temp(g::ExGraph, nd::ExNode{:constant}) = value(nd)

function expand_temp(g::ExGraph, nd::ExNode{:call})
    deps = dependencies(nd)
    expanded = Dict([(x, expand_temp(g, g[x])) for x in deps])
    return subs(expr(nd), expanded)
end

function expand_temp(g::ExGraph, x::Symbol)
    if haskey(g.idx, x)
        return expand_temp(g, g[x])
    else
        return x
    end
end

function expand_temp(g::ExGraph, ex::Expr)
    new_args = [expand_temp(g, arg) for arg in ex.args]
    return Expr(ex.head, new_args...)
end

expand_temp(g::ExGraph, x) = x


    
    


## parse!

"""
Parse Julia expression and build ExGraph in-place.
Return the name of the output variable.
"""
parse!(g::ExGraph, ex::Expr) = parse!(g, to_exh(ex))
parse!(g::ExGraph, ::LineNumberNode) = (:nil, Symbol[])
parse!(g::ExGraph, ::ExH{:line}) = (:nil, Symbol[])
parse!(g::ExGraph, s::Symbol) = (s, Symbol[])
parse!(g::ExGraph, gr::GlobalRef) = (gr, Symbol[])

function parse!(g::ExGraph, x::Number)
    var = addnode!(g, :constant, genname(g), x; val=x)
    return var, Symbol[]
end

function parse!(g::ExGraph, x::AbstractArray)
    name = addnode!(g, :constant, genname(g), x; val=x)
    return name, Symbol[]
end

split_indexed(name::Symbol) = (name, Symbol[])
split_indexed(ex::Expr) = (ex.args[1], convert(Vector{Symbol}, ex.args[2:end]))


function parse!(g::ExGraph, ex::ExH{:(=)})
    lhs, rhs = ex.args
    var, varidxs = split_indexed(lhs)
    dep, depidxs = parse!(g, rhs)
    idxs = Vector{Symbol}[varidxs, depidxs]
    addnode!(g, :(=), var, dep; idxs=idxs)
    return var, varidxs
end


function parse!(g::ExGraph, ex::ExH{:ref})
    return ex.args[1], convert(Vector{Symbol}, ex.args[2:end])
end


function parse!(g::ExGraph, ex::ExH{:call})
    op = canonical(g.mod, ex.args[1])
    deps, depidxs = unzip([parse!(g, arg) for arg in ex.args[2:end]])
    sex = Expr(:call, op, deps...)
    varidxs = forall_indices(op, depidxs)
    idxs = insert!(copy(depidxs), 1, varidxs)
    var = addnode!(g, :call, genname(g), sex; idxs=idxs)
    return var, varidxs
end

function parse!(g::ExGraph, ex::ExH{:block})
    name_idxs = [parse!(g, subex) for subex in ex.args]
    return name_idxs[end]
end

function parse!(g::ExGraph, ex::ExH{:body})
    name_idxs = [parse!(g, subex) for subex in ex.args]
    return name_idxs[end]
end


## evaluate!

"""
Evaluate node, i.e. fill its `val` by evaluating node's expression using
values of its dependencies.
"""
evaluate!(g::ExGraph, node::ExNode{:constant}) = node.val
evaluate!(g::ExGraph, node::ExNode{:input}) = node.val




function mk_eval_expr(g::ExGraph, nd::ExNode)
    dep_nodes = [g.idx[dep] for dep in dependencies(nd)]
    deps_vals = [(nd.var, nd.val) for nd in dep_nodes]
    block = Expr(:block)
    for (dep, val) in deps_vals
        push!(block.args, Expr(:(=), dep, val))
    end
    push!(block.args, isindexed(nd) ? to_einsum_expr(nd) : to_expr(nd))
    push!(block.args, nd.var)
    return block
end


function evaluate!(g::ExGraph, nd::ExNode{:(=)})
    if (nd.val != nothing) return nd.val end
    depnd = g.idx[dependencies(nd)[1]]
    evaluate!(g, depnd)
    evex = mk_eval_expr(g, nd)
    nd.val = eval(evex)
    return nd.val
end

function evaluate!(g::ExGraph, nd::ExNode{:call})
    if (nd.val != nothing) return nd.val end
    # TODO: dep may be a global constant (like π)
    dep_nodes = [g.idx[dep] for dep in dependencies(nd)]
    for depnd in dep_nodes
        evaluate!(g, depnd)
    end
    evex = mk_eval_expr(g, nd)
    nd.val = eval(evex)
    return nd.val
end

evaluate!(g::ExGraph, name::Symbol) = evaluate!(g, g.idx[name])
