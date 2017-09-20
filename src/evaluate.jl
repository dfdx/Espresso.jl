
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
            warn("Using @einsum to evaluate node: $nd")
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



"""
Evaluate node, i.e. fill its `val` by evaluating node's expression using
values of its dependencies.
"""
function evaluate!(g::ExGraph, nd::ExNode{:constant}; force=false)
    ex = getexpr(nd)
    if getvalue(nd) == nothing && (isa(ex, Symbol) || isa(ex, Expr))
        # constant expression - need to evaluate it
        evex = mk_eval_expr(g, nd)
        val = eval(g.ctx[:mod], evex)
        setvalue!(nd, val)
    end
    remember_size!(g, nd)
    return getvalue(nd)
end


function evaluate!(g::EinGraph, nd::ExNode{:constant}; force=false)
    # note: in case of broadcasting (e.g. `x[i] = 1.0`) node value may change
    # after evaluation, e.g. become `[1.0, 1.0, 1.0]` instead of `1.0`
    # this is correct and desired behavior; caching value is thus NOT allowed
    val = eval(g.ctx[:mod], mk_eval_expr(g, nd))
    setvalue!(nd, val)
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
    evaluate!(g, g[dep]; force=force)
    evex = mk_eval_expr(g, nd)
    setvalue!(nd, eval(g.ctx[:mod], evex))
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
    setvalue!(nd, eval(g.ctx[:mod], evex))
    remember_size!(g, nd)
    return getvalue(nd)
end


evaluate!(g::AbstractExGraph, name::Symbol; force=false) = evaluate!(g, g[name]; force=force)
evaluate!(g::AbstractExGraph; force=false) = evaluate!(g, g[end]; force=force)
