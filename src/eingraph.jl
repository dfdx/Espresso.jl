
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

function with_guards_in_context(f::Function, ctx::Dict, new_guards::Vector{Expr})
    guards = @get_or_create(ctx, :guards, Expr[])
    push!(guards, new_guards...)
    f(guards)
    for i=1:length(new_guards) pop!(guards) end
end


function apply_guards(nd::ExNode, guards::Vector{Expr})
    new_var, var_guards = apply_guards(getvar(nd), guards; anchors=Set(varidxs(nd)))
    new_ex, ex_guards = apply_guards(getexpr(nd), guards)    
    new_guards = unique(vcat(var_guards, ex_guards))
    return copy(nd; var=new_var, ex=new_ex, guards=new_guards)
end


## parse!


function parse!(g::EinGraph, ex::ExH{:(=)})
    ex = Expr(ex)
    ex_ = without_guards(ex)
    var_, rhs = ex_.args
    vname, vidxs = split_indexed(var_)
    with_guards_in_context(g.ctx, find_guards(ex)) do guards        
        var, var_guards = apply_guards(var_, guards; anchors=Set(vidxs))
        dep = parse!(g, rhs)
        push!(g, ExNode{:(=)}(var, dep; guards=var_guards))
    end
    return vname
end


function parse!(g::EinGraph, ex::ExH{:ref})
    return Expr(ex)
end


function parse!(g::EinGraph, ex::ExH{:call})
    # prepare main expression
    ex_ = without_guards(ex)
    op = canonical(g.ctx[:mod], ex_.args[1])
    # prepare guards
    guards = @get_or_create(g.ctx, :guards, Expr[])
    new_guards = find_guards(ex)
    push!(guards, new_guards...)
    # process deps, guards included
    deps = [parse!(g, arg) for arg in ex_.args[2:end]]
    depnames, depidxs = unzip(map(split_indexed, deps))
    # create a new primitive expression
    pex, pex_guards = apply_guards(Expr(:call, op, deps...), guards)
    vidxs = forall_indices(op, [split_indexed(dep)[2] for dep in deps])
    var, _ = apply_guards(make_indexed(genname(), vidxs), guards)
    push!(g, ExNode{:call}(var, pex; guards=pex_guards))
    # pop new guards
    for i=1:length(new_guards) pop!(guards) end
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
