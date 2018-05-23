
function rename!(g::AbstractExGraph, name::Symbol, new_name::Symbol)
    return rename!(g, Dict(name => new_name))
end


function rename!(g::AbstractExGraph, st::Dict{Symbol,Symbol})
    for nd in g.tape
        var = getvar(nd)
        new_var = subs(var, st)
        setvar!(nd, subs(var, st))
        setexpr!(nd, subs(getexpr(nd), st))
        delete!(g.idx, var)
        g.idx[new_var] = nd
    end
    return g
end

function rename(g::AbstractExGraph, st::Dict{Symbol,Symbol})
    new_g = reset_tape(g)
    for nd in g.tape
        push!(new_g, copy(nd; var=subs(getvar(nd), st), ex=subs(getexpr(nd), st)))
    end
    return new_g
end


function mergeex(g1::AbstractExGraph, g2::AbstractExGraph)
    g2 = deepcopy(g2)
    @assert typeof(g1) == typeof(g2)
    gm = typeof(g1)()
    # find out what vars in g2 need to be renamed
    g1_vars = Set(varname(nd) for nd in g1.tape)
    g2_vars = Set(varname(nd) for nd in g2.tape)
    need_renaming = Symbol[]
    for nd in g2.tape
        vname = varname(nd)
        if haskey(g1, vname) && getexpr(g1[vname]) != getexpr(nd)
            push!(need_renaming, vname)
        end
    end
    # rename variables in g2
    new_names = gennames(length(need_renaming))
    for (name, new_name) in zip(need_renaming, new_names)
        rename!(g2, name, new_name)
    end
    # concat graphs
    for nd in g1.tape
        push!(gm, nd)
    end
    for nd in g2.tape
        if !haskey(gm, varname(nd))
            push!(gm, nd)
        end
    end
    return gm
end


function mergeex(gs::Vararg{AbstractExGraph})
    return reduce(mergeex, gs)
end


function mergeex(exs::Vararg{Expr})
    indexed = any(isindexed, exs)
    gs = indexed ? [EinGraph(ex) for ex in exs] : [ExGraph(ex) for ex in exs]
    gm = mergeex(gs...)
    block = to_expr(gm)
    res_vars = [g[end].var for g in gs]
    push!(block.args, Expr(:tuple, res_vars...))
    return block
end
