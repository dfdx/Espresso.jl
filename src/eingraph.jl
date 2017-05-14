
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
        push!(g, :input, var, var; val=val)
    end
    return g
end

function EinGraph(ex::Expr; fuse=true, ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    g = EinGraph(;ctx=ctx, inputs...)
    g.ctx[:expr] = ex
    parse!(g, ex)
    if fuse
        g = fuse_equal(g)
    end
    return g
end


function Base.show(io::IO, g::EinGraph)
    print(io, "EinGraph\n")
    for node in g.tape
        print(io, "  $node\n")
    end
end


## utils

# function with_guards_in_context(f::Function, ctx::Dict, new_guards::Vector{Expr})
#     guards = @get_or_create(ctx, :guards, Expr[])
#     push!(guards, new_guards...)
#     f(guards)
#     for i=1:length(new_guards) pop!(guards) end
# end


function push_guards!(ctx::Dict, new_guards::Vector{Expr})
    guards = @get_or_create(ctx, :guards, Expr[])
    push!(guards, new_guards...)
    last_guard_counts = @get_or_create(ctx, :last_guard_counts, [])
    push!(last_guard_counts, length(new_guards))
    return guards
end


function pop_guards!(ctx::Dict)
    guards = ctx[:guards]
    last_guard_counts = ctx[:last_guard_counts]
    for i=1:last_guard_counts[end]
        pop!(guards)
    end
    pop!(last_guard_counts)
end



# function apply_guards(nd::ExNode, guards::Vector{Expr})
#     new_var, var_guards = apply_guards(getvar(nd), guards; anchors=Set(varidxs(nd)))
#     new_ex, ex_guards = apply_guards(getexpr(nd), guards)
#     new_guards = unique(vcat(var_guards, ex_guards))
#     return copy(nd; var=new_var, ex=new_ex, guards=new_guards)
# end


## parse!


function parse!(g::EinGraph, ex::ExH{:(=)})
    ex = Expr(ex)
    ex_ = without_guards(ex)
    var, rhs = ex_.args
    vname, vidxs = split_indexed(var)
    guards = push_guards!(g.ctx, find_guards(ex))    
    dep = parse!(g, rhs)
    depidxs = split_indexed(dep)[2]
    st, new_guards = reduce_guards(guards; keep=vidxs, used=vcat(vidxs, depidxs))
    push!(g, ExNode{:(=)}(var, subs(dep, st); guards=new_guards))
    pop_guards!(g.ctx)
    return var
end


function parse!(g::EinGraph, ex::ExH{:ref})
    return Expr(ex)
end


function parse!(g::EinGraph, ex::ExH{:call})
    ex = Expr(ex)
    ex_ = without_guards(ex)
    op = canonical(g.ctx[:mod], ex_.args[1])
    guards = push_guards!(g.ctx, find_guards(ex))
    deps = [parse!(g, arg) for arg in ex_.args[2:end]]
    depnames, depidxs = unzip(map(split_indexed, deps))
    pex_ = Expr(:call, op, deps...)
    st, pex_guards = reduce_guards(guards; )
    pex = subs(pex_, st)
    vidxs = forall_indices(op, [split_indexed(dep)[2] for dep in deps])
    var = make_indexed(genname(), vidxs)
    push!(g, ExNode{:call}(var, pex; guards=pex_guards))
    pop_guards!(g.ctx)
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
    var = push!(g, :bcast, make_indexed(genname(), vidxs), pex)
    return var
end


function parse!(g::EinGraph, ex::ExH{Symbol("'")})
    error(":' is not allowed in Einstin notation")
end


function parse!(g::EinGraph, ex::ExH{:tuple})
    deps = [parse!(g, arg) for arg in ex.args]
    pex = Expr(:tuple, deps...)
    vname = push!(g, :tuple, genname(), pex)
end

## evaluate!

# see exgraph.jl
