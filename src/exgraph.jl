
# exgraph.jl - expression graph as a list of primitive expression nodes

abstract type AbstractExGraph end

mutable struct ExGraph <: AbstractExGraph
    tape::Vector{ExNode}           # list of ExNode-s
    idx::Dict{Symbol, ExNode}      # map from var name to its node in the graph
    ctx::Dict{Any,Any}             # settings and caches
end

function ExGraph(; ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    @get_or_create(ctx, :mod, current_module())
    g = ExGraph(ExNode[], Dict(), ctx)
    for (var, val) in inputs
        push!(g, :input, var, var; val=val)
    end
    return g
end

function ExGraph(ex::Expr; fuse=true, ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    g = ExGraph(;ctx=ctx, inputs...)
    g.ctx[:expr] = ex
    parse!(g, ex)
    if fuse
        g = fuse_assigned(g)
    end
    return g
end


function Base.deepcopy(g::AbstractExGraph)
    ctx_copy = to_context(Dict())
    for (k, v) in g.ctx
        if isa(v, Module)
            ctx_copy[k] = v
        else
            ctx_copy[k] = deepcopy(v)
        end
    end
    return typeof(g)(deepcopy(g.tape), deepcopy(g.idx), ctx_copy)
end


function Base.show(io::IO, g::ExGraph)
    print(io, "ExGraph\n")
    for node in g.tape
        print(io, "  $node\n")
    end
end

Base.haskey(g::AbstractExGraph, var::Symbol) = haskey(g.idx, var)
Base.endof(g::AbstractExGraph) = endof(g.tape)
Base.length(g::AbstractExGraph) = length(g.tape)
Base.get(g::AbstractExGraph, var::Symbol) = g.idx[var]
Base.getindex(g::AbstractExGraph, var::Symbol) = g.idx[var]
Base.getindex(g::AbstractExGraph, var::String) = g.idx[Symbol(var)]
Base.getindex(g::AbstractExGraph, i::Integer) = g.tape[i]
Base.setindex!(g::AbstractExGraph, nd::ExNode, i::Integer) =
    (g.tape[i] = nd; g.idx[varname(nd)] = nd)

indexof(g::AbstractExGraph, vname::Symbol) = findfirst(map(varname, g.tape), vname)


function Base.cat(g1::T, g2::T) where T<:AbstractExGraph
    return T(vcat(g1.tape, g2.tape), merge(g1.idx, g2.idx), merge(g1.ctx, g2.ctx))
end


function to_expr(g::AbstractExGraph)
    res = quote end
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            push!(res.args, to_expr(nd))
        end
    end
    return res
end


"""Generate a new unique name for intermediate variable in graph"""
function genname()
    s = String(gensym())
    return Symbol(replace(s, "##", "tmp"))
end


function gennames(count::Int)
    return [genname() for _=1:count]
end

## push!, insert!, delete!

"""
Add a new node to a graph. Expression should be simple, e.g.
nested calls or blocks are not allowed (use parse!() for it).
"""
function Base.push!(g::AbstractExGraph, nd::ExNode)
    push!(g.tape, nd)
    g.idx[varname(nd)] = nd
    return varname(nd)
end

function Base.push!(g::AbstractExGraph, C::Symbol, var::Union{Symbol,Expr}, ex::Any; val=nothing)
    nd = ExNode{C}(var, ex; val=val)
    push!(g, nd)
    return var
end


function Base.insert!(g::AbstractExGraph, i::Integer, nd::ExNode)
    g.idx[varname(nd)] = nd
    insert!(g.tape, i, nd)
end


function Base.insert!(g::AbstractExGraph, i::Integer, nds::Vector{ExNode})
    for (j, nd) in enumerate(nds)
        insert!(g, i + j - 1, nd)
    end
end


function Base.delete!(g::AbstractExGraph, i::Integer)
    delete!(g.idx, varname(g[i]))
    deleteat!(g.tape, i)
end


function Base.delete!(g::AbstractExGraph, vname::Symbol)
    delete!(g.idx, vname)
    i = find(nd -> varname(nd) == vname, g.tape)
    deleteat!(g.tape, i)
end


## parse!

"""
Parse Julia expression and build ExGraph in-place.
Return the the output variable.
"""
parse!(g::AbstractExGraph, ex::Expr) = parse!(g, ExH(ex))
parse!(g::AbstractExGraph, ::LineNumberNode) = :nil
parse!(g::AbstractExGraph, ::ExH{:line}) = :nil
parse!(g::AbstractExGraph, s::Symbol) = s
# parse!(g::ExGraph, gr::GlobalRef) = (gr, [])

function parse!(g::AbstractExGraph, x::Number)
    var = push!(g, :constant, genname(), x; val=x)
    return var
end


function parse!(g::AbstractExGraph, x::AbstractArray)
    var = push!(g, :constant, genname(), x; val=x)
    return var
end


function parse!(g::ExGraph, ex::ExH{:(=)})
    vname, rhs = ex.args
    dep = parse!(g, rhs)
    push!(g, :(=), vname, dep)
    return vname
end


function parse!(g::ExGraph, ex::ExH{:ref})
    error("Indexing is not currently allowed in vectorized expression")
    # return Expr(ex)
end


function parse!(g::ExGraph, ex::ExH{:call})
    op = canonical(g.ctx[:mod], ex.args[1])
    deps = [parse!(g, arg) for arg in ex.args[2:end]]
    pex = Expr(:call, op, deps...)
    var = push!(g, :call, genname(), pex)
    return var
end


function parse!(g::ExGraph, ex::ExH{:.})
    @assert(isa(ex.args[2], Expr) && ex.args[2].head == :tuple,
            "Dot (.) is only allowedd in broadcasting (e.g. `f.(x)`), but `$ex` passed in")
    op = canonical(g.ctx[:mod], ex.args[1])
    deps = [parse!(g, arg) for arg in ex.args[2].args]
    # pex = Expr(:call, op, deps...)
    pex = Expr(:., op, Expr(:tuple, deps...))
    var = push!(g, :bcast, genname(), pex)
    return var
end


function parse!(g::ExGraph, ex::ExH{Symbol("'")})
    dep = parse!(g, ex.args[1])
    pex = :(transpose($dep))
    var = push!(g, :call, genname(), pex)
    return var
end


function parse!(g::AbstractExGraph, ex::Union{ExH{:block}, ExH{:body}})
    deps = [parse!(g, arg) for arg in ex.args]
    return deps[end]
end


function parse!(g::ExGraph, ex::ExH{:tuple})
    deps = [parse!(g, arg) for arg in ex.args]
    pex = Expr(:tuple, deps...)
    vname = push!(g, :tuple, genname(), pex)
end


## evaluate!

function remember_size!(g::AbstractExGraph, nd::ExNode)
    rsizes = @get_or_create(g.ctx, :rsizes, Dict{Symbol,Any}())
    buff_exprs = @get_or_create(g.ctx, :buff_exprs, Dict{Symbol, Any}())
    val = getvalue(nd)
    sz = size(val)
    rsizes[varname(nd)] = sz
    if isa(val, Array)
        T = eltype(val)
        buff_expr = :(zeros($T, $sz))
    else
        T = typeof(val)
        buff_expr = :(zero($T))
    end
    buff_exprs[varname(nd)] = buff_expr
end

function remember_size!(g::AbstractExGraph, nd::ExNode{:tuple}) end


"""
Evaluate node, i.e. fill its `val` by evaluating node's expression using
values of its dependencies.
"""
function evaluate!(g::AbstractExGraph, nd::ExNode{:constant}; force=false)
    remember_size!(g, nd)
    return getvalue(nd)
end

function evaluate!(g::AbstractExGraph, nd::ExNode{:input}; force=false)
    remember_size!(g, nd)
    return getvalue(nd)
end


function isconv(nd::ExNode)
    idxs = nd |> getexpr |> get_indices |> flatten
    return any(i -> isa(i, Expr), idxs)
end


function mk_eval_expr(g::ExGraph, nd::ExNode)
    dep_nodes = [g[dep] for dep in dependencies(nd) if haskey(g, dep)]
    deps_vals = [(varname(nd), getvalue(nd)) for nd in dep_nodes]
    eval_ex = Expr(:block, Expr(:let, Expr(:block)))
    block = eval_ex.args[1].args[1]
    for (dep, val) in deps_vals
        push!(block.args, :(local $dep = $val))
    end
    push!(block.args, to_expr(nd))
    push!(block.args, varname(nd))
    return eval_ex
end


function mk_eval_expr(g::AbstractExGraph, nd::ExNode)   # for EinGraph
    rsizes = @get_or_create(g.ctx, :rsizes, Dict{Symbol,Any}())
    dep_nodes = [g[dep] for dep in dependencies(nd) if haskey(g, dep)]
    deps_vals = [(varname(nd), getvalue(nd)) for nd in dep_nodes]
    eval_ex = Expr(:block, Expr(:let, Expr(:block)))
    block = eval_ex.args[1].args[1]
    for (dep, val) in deps_vals
        push!(block.args, :(local $dep = $val))
    end
    try
        # try to convert to vectorized notation for speed and to cover things like `x[i,j] = 1.0`
        subex = from_einstein(g, nd)
        subex = subs_size(subex, rsizes)
        subex = subs_bcast_with_dot(subex)
        push!(block.args, subex)
    catch
        if !isindexed(nd)
            push!(block.args, to_expr(nd))
        elseif isconv(nd)
            push!(block.args, from_einstein(g, nd))
        elseif getcategory(nd) == :tuple
            push!(block.args, without_indices(to_expr(nd)))
        else
            vname = varname(nd)
            if haskey(rsizes, vname)
                # provide size if available
                push!(block.args, to_einsum_expr(nd, rsizes[vname]).args...)
            else
                # otherwise let Einsum to try to infer the size
                push!(block.args, to_einsum_expr(nd).args...)
            end
        end
    end
    push!(block.args, varname(nd))
    return eval_ex
end

# function mk_eval_expr(g::AbstractExGraph, nd::ExNode)
#     dep_nodes = [g[dep] for dep in dependencies(nd) if haskey(g, dep)]
#     deps_vals = [(varname(nd), getvalue(nd)) for nd in dep_nodes]
#     eval_ex = Expr(:block, Expr(:let, Expr(:block)))
#     block = eval_ex.args[1].args[1]
#     for (dep, val) in deps_vals
#         push!(block.args, :(local $dep = $val))
#     end
#     if isindexed(nd)
#         try
#             # the problem: from_einstein requires inputs to determine size
#             push!(block.args, from_einstein(g, nd))
#         catch
#             println("falling back to Einsum for $nd")
#             subex = to_einsum_expr(nd)
#             println("subex = $subex")
#             push!(block.args, subex)
#         end
#     else
#         push!(block.args, to_expr(nd))
#     end
#     # push!(block.args, !isindexed(nd) ? to_expr(nd) :
#     #       (isconv(nd) ? from_einstein(g, nd) : to_einsum_expr(nd)))
#     push!(block.args, varname(nd))
#     return eval_ex
# end


function evaluate!(g::AbstractExGraph, nd::ExNode{:(=)}; force=false)
    if (!force && getvalue(nd) != nothing) return getvalue(nd) end
    dep = dependencies(nd)[1]
    evaluate!(g, g[dep]; force=force)
    evex = mk_eval_expr(g, nd)
    setvalue!(nd, eval(evex))
    remember_size!(g, nd)
    return getvalue(nd)
end


function evaluate!(g::AbstractExGraph,
                   nd::Union{ExNode{:call}, ExNode{:bcast},
                             ExNode{:tuple}, ExNode{:opaque}};
                   force=false)
    if (!force && getvalue(nd) != nothing) return getvalue(nd) end
    deps = dependencies(nd)
    for dep in deps
        # if dep is not in graph, consider it a global constant (like π)
        if haskey(g.idx, dep)
            evaluate!(g, g[dep]; force=force)
        end
    end
    evex = mk_eval_expr(g, nd)
    setvalue!(nd, eval(evex))
    remember_size!(g, nd)
    return getvalue(nd)
end


evaluate!(g::AbstractExGraph, name::Symbol; force=false) = evaluate!(g, g[name]; force=force)
evaluate!(g::AbstractExGraph; force=false) = evaluate!(g, g[end]; force=force)


## reparsing of opaque nodes

function reparse(g::AbstractExGraph)
    new_g = reset_tape(g)
    for nd in g.tape
        if isa(nd, ExNode{:opaque})
            parse!(new_g, to_expr(nd))
        else
            push!(new_g, nd)
        end
    end
    return fuse_assigned(new_g)
end


## graph simlification

istemp(var::Symbol) = startswith(string(var), "tmp")


function external_vars(g::AbstractExGraph)
    ext_vnames = Set{Symbol}()
    for nd in g.tape
        for dep in dependencies(nd)
            if !haskey(g, dep)
                push!(ext_vnames, dep)
            end
        end
    end
    return ext_vnames
end


function assign_chain!(g::AbstractExGraph, nd::ExNode{:(=)},
                       guards::Vector{Expr}, chain::Vector{Symbol})
    if getguards(nd) == guards
        push!(chain, varname(nd))
        dep = dependencies(nd)[1]
        if haskey(g, dep) && !isa(g[dep], ExNode{:input})
            dep_nd = g[dep]
            assign_chain!(g, dep_nd, guards, chain)
        end
    end
    return chain
end

function assign_chain!{C}(g::AbstractExGraph, nd::ExNode{C},
                          guards::Vector{Expr}, chain::Vector{Symbol})
    if getguards(nd) == guards
        push!(chain, varname(nd))
    end
end


"""
Collect all replacable variables from a chain of assignments in a graph.
Variables `y` and `x` are considered replacable if there's a node `y = x`
and both variables have the same set of guards.
Note that this allows nodes to have different sets of indices.
"""
assign_chain{C}(g::AbstractExGraph, nd::ExNode{C}) =
    assign_chain!(g, nd, getguards(nd), Vector{Symbol}())



function assign_chain_index_replacements(g::AbstractExGraph, chain::Vector{Symbol})
    nd = g[chain[1]]
    st = Dict(zip(varidxs(nd), varidxs(nd)))
    for i=2:length(chain)
        prev_idxs = get_indices(getexpr(g[chain[i-1]]))[1]
        cur_idxs = varidxs(g[chain[i]])
        pair_st = Dict(zip(prev_idxs, cur_idxs))
        new_st = Dict()
        for (k, v) in st
            if haskey(pair_st, v)
                # propagate replacements
                new_st[k] = pair_st[v]
            end
        end
        st = new_st
    end
    return Dict(zip(values(st), keys(st)))
end


"""
Collapse unnecessary assignment nodes, rewriting all affected nodes. Example:

    tmp1 = x * y
    z = tmp1

will be rewritten to

    z = x * y
"""
function fuse_assigned(g::AbstractExGraph; outvars=nothing)
    new_g = reset_tape(g)
    for nd in g.tape
        if isa(nd, ExNode{:(=)})
            chain = assign_chain(g, nd)
            root_assign_nd = g[chain[end]]
            new_ex_ = getexpr(root_assign_nd)
            new_ex = subs(new_ex_, assign_chain_index_replacements(g, chain))
            new_nd = copy(root_assign_nd; var=getvar(nd), ex=new_ex)
            push!(new_g, new_nd)
        else
            push!(new_g, copy(nd))
        end
    end
    new_g = remove_unused(new_g, outvars == nothing ? [varname(new_g[end])] : outvars)
    return new_g
end
