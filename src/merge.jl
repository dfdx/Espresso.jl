
function rename!(g::ExGraph, name::Symbol, new_name::Symbol)
    st = Dict(name => new_name)
    for nd in g.tape
        if nd.var == name
            nd.var = new_name
        end
        nd.ex = subs(nd.ex, st)
    end
    return g
end


function mergeex(g1::ExGraph, g2::ExGraph)
    g2 = deepcopy(g2)
    gm = ExGraph()
    # find out what vars in g2 need to be renamed
    g1_vars = Set(varname(nd) for nd in g1.tape)
    g2_vars = Set(varname(nd) for nd in g2.tape)
    need_renaming = Symbol[]
    for nd in g2.tape
        vname = varname(nd)
        if haskey(g1, vname) && expr(g1[vname]) != expr(nd)
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
        addnode!(gm, nd)
    end
    for nd in g2.tape
        if !haskey(gm, varname(nd))
            addnode!(gm, nd)
        end
    end
    return gm
end


function mergeex(gs::Vararg{ExGraph})
    return reduce(mergeex, gs)
end


function mergeex(exs::Vararg{Expr})
    gs = [ExGraph(ex) for ex in exs]
    gm = mergeex(gs...)
    block = to_expr(gm)
    res_vars = [g[end].var for g in gs]
    push!(block.args, Expr(:tuple, res_vars...))
    return block
end
