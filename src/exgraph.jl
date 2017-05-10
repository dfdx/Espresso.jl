
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
        g = fuse_equal(g)
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


function Base.cat(g1::AbstractExGraph, g2::AbstractExGraph)
    @assert typeof(g1) == typeof(g2)
    return typeof(g1)(vcat(g1.tape, g2.tape), merge(g1.idx, g2.idx), merge(g1.ctx, g2.ctx))
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

"""
Evaluate node, i.e. fill its `val` by evaluating node's expression using
values of its dependencies.
"""
evaluate!(g::AbstractExGraph, nd::ExNode{:constant}) = getvalue(nd)
evaluate!(g::AbstractExGraph, nd::ExNode{:input}) = getvalue(nd)


function mk_eval_expr(g::AbstractExGraph, nd::ExNode)
    dep_nodes = [g[dep] for dep in dependencies(nd) if haskey(g, dep)]
    deps_vals = [(varname(nd), getvalue(nd)) for nd in dep_nodes]
    eval_ex = Expr(:block, Expr(:let, Expr(:block)))
    block = eval_ex.args[1].args[1]
    for (dep, val) in deps_vals
        push!(block.args, :(local $dep = $val))
    end
    push!(block.args, isindexed(nd) ? to_einsum_expr(nd) : to_expr(nd))
    push!(block.args, varname(nd))
    return eval_ex
end


function evaluate!(g::AbstractExGraph, nd::ExNode{:(=)})
    if (getvalue(nd) != nothing) return getvalue(nd) end
    dep = dependencies(nd)[1]
    evaluate!(g, g[dep])
    evex = mk_eval_expr(g, nd)
    setvalue!(nd, eval(evex))
    return getvalue(nd)
end

function evaluate!(g::AbstractExGraph, nd::ExNode{:call})
    if (getvalue(nd) != nothing) return getvalue(nd) end
    deps = dependencies(nd)
    for dep in deps
        # if dep is not in graph, consider it a global constant (like π)
        if haskey(g.idx, dep)
            evaluate!(g, g[dep])
        end
    end
    evex = mk_eval_expr(g, nd)
    setvalue!(nd, eval(evex))
    return getvalue(nd)
end


function evaluate!(g::AbstractExGraph, nd::ExNode{:bcast})
    if (getvalue(nd) != nothing) return getvalue(nd) end
    deps = dependencies(nd)
    for dep in deps
        # if dep is not in graph, consider it a global constant (like π)
        if haskey(g.idx, dep)
            evaluate!(g, g[dep])
        end
    end
    evex = mk_eval_expr(g, nd)
    setvalue!(nd, eval(evex))
    return getvalue(nd)
end



evaluate!(g::AbstractExGraph, name::Symbol) = evaluate!(g, g[name])
evaluate!(g::AbstractExGraph) = evaluate!(g, g[end])


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


"""
Collapse unnecessary assignment nodes, rewriting all affected nodes. Example:

    tmp1 = x * y
    z = tmp1

will be rewritten to

    z = x * y
"""
function fuse_equal(g::AbstractExGraph; outvars=nothing)
    st = Dict{Symbol, Symbol}()
    for nd in g.tape
        if isa(nd, ExNode{:(=)})
            vname = varname(nd)
            dep = dependencies(nd)[1]
            if istemp(dep)
                # if dependency is a temp var name, replace it with the normal one
                st[dep] = vname
            else
                # otherwise replace all future alias occurrences with the original one
                st[vname] = dep
            end
        end
    end
    st = prop_subs(st)
    new_g = reset_tape(g)
    replace_vars = Set(values(st))
    for nd in g.tape
        vname = varname(nd)
        if in(vname, replace_vars)
            dep_nd = nd
            while isa(dep_nd, ExNode{:(=)}) && haskey(g, dependencies(dep_nd)[1])
                # go through graph to the first non-assignment node
                dep_nd = g[dependencies(dep_nd)[1]]
            end
            new_nd_ = copy(dep_nd; var=subs(getvar(nd), st))
            new_nd = apply_guards(new_nd_, vcat(getguards(nd), getguards(dep_nd)))
            push!(new_g, new_nd)
        else
            push!(new_g, nd)
        end
    end
    new_g = remove_unused(new_g, outvars == nothing ? [varname(new_g[end])] : outvars)
    return new_g
end


# function fuse_equal!(g::AbstractExGraph)
#     ext_vars = external_vars(g)
#     st = Dict{Symbol, Symbol}()
#     delvars = Set{Symbol}()
#     for nd in g.tape
#         setexpr!(nd, subs(getexpr(nd), st))
#         vidxs = varidxs(nd)
#         depidxs = get_indices(getexpr(nd))
#         if isa(nd, ExNode{:(=)}) && !isempty(depidxs) && vidxs == depidxs[1]
#             vname = varname(nd)
#             dep = dependencies(nd)[1]
#             if !in(dep, ext_vars)  # can't remove external vars
#                 if istemp(dep)
#                     # if dependency is a temp var name, replace it with the normal one
#                     st[dep] = vname
#                     push!(delvars, vname)
#                 else
#                     # otherwise replace all future alias occurrences with the original one
#                     st[vname] = dep
#                     push!(delvars, vname)
#                 end
#             end
#         end
#     end
#     new_tape = Vector{ExNode}()
#     new_idx = Dict{Symbol, ExNode}()
#     for nd in g.tape
#         vname = varname(nd)
#         if !in(vname, delvars)
#             if haskey(st, vname)
#                 new_nd = deepcopy(nd)
#                 setvar!(new_nd, subs(getvar(nd), st))
#                 setexpr!(new_nd, subs(getexpr(nd), st))
#                 push!(new_tape, new_nd)
#                 new_idx[varname(new_nd)] = new_nd
#             else
#                 push!(new_tape, nd)
#                 new_idx[varname(nd)] = nd
#             end
#         end
#     end
#     g.tape = new_tape
#     g.idx = new_idx
#     return g
# end


# collapse_assignments! = fuse_equal!
