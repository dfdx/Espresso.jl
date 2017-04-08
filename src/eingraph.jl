
# eingraph.jl - sibling of ExGraph for Einstein indexing notation

mutable struct EinGraph <: AbstractExGraph
    tape::Vector{ExNode}           # list of ExNode-s
    idx::Dict{Symbol, ExNode}      # map from var name to its node in the graph
    ctx::Dict{Any,Any}             # settings and caches
end

function EinGraph(; ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    @get_or_create(ctx, :mod, current_module())
    g = EinGraph(ExNode[], Dict(), ctx)
    for (var, val) in inputs
        addnode!(g, :input, var, var; val=val)
    end
    return g
end

function EinGraph(ex::Expr; ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    g = EinGraph(;ctx=ctx, inputs...)
    g.ctx[:expr] = ex
    parse!(g, ex)
    collapse_assignments!(g)
    return g
end


function Base.show(io::IO, g::EinGraph)
    print(io, "EinGraph\n")
    for node in g.tape
        print(io, "  $node\n")
    end
end



## parse!


function parse!(g::EinGraph, ex::ExH{:(=)})
    var, rhs = ex.args
    vname = split_indexed(var)[1]
    dep = parse!(g, rhs)
    addnode!(g, :(=), var, dep)
    return vname
end


function parse!(g::EinGraph, ex::ExH{:ref})
    return Expr(ex)
end


function parse!(g::EinGraph, ex::ExH{:call})
    op = canonical(g.ctx[:mod], ex.args[1])
    deps = [parse!(g, arg) for arg in ex.args[2:end]]
    depnames, depidxs = unzip(map(split_indexed, deps))
    pex = Expr(:call, op, deps...)
    vidxs = forall_indices(op, [split_indexed(dep)[2] for dep in deps])
    var = addnode!(g, :call, make_indexed(genname(), vidxs), pex)
    return var
end


function parse!(g::EinGraph, ex::ExH{:.})
    @assert(isa(ex.args[2], Expr) && ex.args[2].head == :tuple,
            "Dot (.) is only allowedd in broadcasting (e.g. `f.(x)`), but `$ex` passed in")
    op = canonical(g.ctx[:mod], ex.args[1])
    deps = [parse!(g, arg) for arg in ex.args[2].args]
    # pex = Expr(:call, op, deps...)
    pex = Expr(:., op, Expr(:tuple, deps...))
    vidxs = forall_indices(op, [split_indexed(dep)[2] for dep in deps])
    var = addnode!(g, :bcast, make_indexed(genname(), vidxs), pex)
    return var
end


function parse!(g::EinGraph, ex::ExH{Symbol("'")})
    error(":' is not allowed in Einstin notation")
end


## evaluate!

# see exgraph.jl

