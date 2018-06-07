
## evaluate.jl - evaluation of graph


function remember_size!(g::AbstractExGraph, nd::ExNode)
    rsizes = @get_or_create(g.ctx, :rsizes, Dict{Symbol,Any}())
    buff_exprs = @get_or_create(g.ctx, :buff_exprs, Dict{Symbol, Any}())
    val = getvalue(nd)
    if isa(val, AbstractArray) || isa(val, Number)
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
end

function remember_size!(g::AbstractExGraph, nd::ExNode{:tuple}) end


function isconv(nd::ExNode)
    depwarn_eingraph(:isconv)
    idxs = nd |> getexpr |> get_indices |> flatten
    return any(i -> isa(i, Expr), idxs)
end


function mk_eval_expr(g::ExGraph, nd::ExNode)
    dep_nodes = [g[dep] for dep in dependencies(nd) if haskey(g, dep)]
    deps_vals = Dict((varname(nd), getvalue(nd)) for nd in dep_nodes)
    evex = Expr(:block)
    for dep in unique(keys(deps_vals))
        val = deps_vals[dep]
        push!(evex.args, :(local $dep = $val))
    end
    codegen = eval_codegen(@get(g.ctx, :codegen, VectorCodeGen()))
    push!(evex.args, generate_code(codegen, g, nd))
    push!(evex.args, varname(nd))
    return evex
end


function mk_eval_expr(g::ExGraph, nd::ExNode{:ctor})
    dep_nodes = [g[dep] for dep in dependencies(nd) if haskey(g, dep)]
    deps_vals = Dict((varname(nd), getvalue(nd)) for nd in dep_nodes)
    evex = Expr(:block)
    for dep in unique(keys(deps_vals))
        val = deps_vals[dep]
        push!(evex.args, :(local $dep = $val))
    end    
    push!(evex.args, to_expr_kw(nd))
    push!(evex.args, varname(nd))
    return evex
end

# function mk_eval_expr(g::ExGraph, nd::ExNode{:ctor})
#     dep_nodes = [g[dep] for dep in dependencies(nd) if haskey(g, dep)]
#     deps_vals = [(varname(nd), getvalue(nd)) for nd in dep_nodes]
#     eval_ex = Expr(:block, Expr(:let, Expr(:block)))
#     block = eval_ex.args[1].args[1]
#     for (dep, val) in unique(deps_vals)
#         push!(block.args, :(local $dep = $val))
#     end
#     push!(block.args, to_expr_kw(nd))
#     push!(block.args, varname(nd))
#     return eval_ex
# end


"""
Evaluate node, i.e. fill its `val` by evaluating node's expression using
values of its dependencies.
"""
function evaluate!(g::ExGraph, nd::ExNode{:constant}; force=false)
    ex = getexpr(nd)
    if getvalue(nd) == nothing && (isa(ex, Symbol) || isa(ex, Expr))
        # constant expression - need to evaluate it
        evex = mk_eval_expr(g, nd)
        val = Core.eval(g.ctx[:mod], evex)
        setvalue!(nd, val)
    end
    remember_size!(g, nd)
    return getvalue(nd)
end


function evaluate!(g::AbstractExGraph, nd::ExNode{:input}; force=false)
    remember_size!(g, nd)
    return getvalue(nd)
end


function evaluate!(g::AbstractExGraph, nd::ExNode{:(=)}; force=false)
    if (!force && getvalue(nd) != nothing) return getvalue(nd) end
    dep = dependencies(nd)[1]
    evaluate!(g, g[dep]; force=false)
    evex = mk_eval_expr(g, nd)
    setvalue!(nd, Core.eval(g.ctx[:mod], evex))
    remember_size!(g, nd)
    return getvalue(nd)
end


# nd::Union{ExNode{:call}, ExNode{:bcast}, ExNode{:ctor},
# ExNode{:tuple}, ExNode{:opaque}}
function evaluate!(g::AbstractExGraph, nd::ExNode; force=false)
    if (!force && getvalue(nd) != nothing) return getvalue(nd) end
    deps = dependencies(nd)
    for dep in deps
        # if dep is not in graph, consider it a global constant (like π)
        if haskey(g.idx, dep)
            evaluate!(g, g[dep]; force=false)  # force affects only current node
        end
    end
    evex = mk_eval_expr(g, nd)
    setvalue!(nd, Core.eval(g.ctx[:mod], evex))
    remember_size!(g, nd)
    return getvalue(nd)
end


function evaluate!(g::AbstractExGraph, nd::ExNode{:field}; force=false)
    if (!force && getvalue(nd) != nothing) return getvalue(nd) end
    depnd = g[dependencies(nd)[1]]
    obj = getvalue(depnd)
    fld = getexpr(nd).args[2].value
    val = getfield(obj, fld)
    setvalue!(nd, val)
    remember_size!(g, nd)
    return getvalue(nd)
end


evaluate!(g::AbstractExGraph, name::Symbol; force=false) = evaluate!(g, g[name]; force=force)

function evaluate!(g::AbstractExGraph; force=false)
    for i=1:length(g)
        try
            evaluate!(g, g[i]; force=force)
        catch e
            mod = @get(g.ctx, :mod, nothing)
            @info("Failed to evaluate node (in module $mod): $(g[i])")
            throw(e)
        end
    end
    return getvalue(g[end])
end
