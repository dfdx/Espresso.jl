
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




function expr_merge(g1::ExGraph, g2::ExGraph)
    g2 = deepcopy(g2)
    gm = ExGraph(:(no + expr), false)
    # find out what vars in g2 need to be renamed
    g1_vars = Set(nd.var for nd in g1.tape)
    g2_vars = Set(nd.var for nd in g1.tape)
    need_renaming = Symbol[]
    for nd in g2.tape
        if haskey(g1, nd.var) && expr(g1[nd.var]) != expr(nd)
            push!(need_renaming, nd.var)
        end
    end
    # rename variables in g2
    new_names = gennames(1, union(g1_vars, g2_vars), length(need_renaming))
    for (name, new_name) in zip(need_renaming, new_names)
        rename!(g2, name, new_name)
    end
    # concat graphs
    for nd in g1.tape
        addnode!(gm, nd)
    end
    for nd in g2.tape
        if !haskey(gm, nd.var)           
            addnode!(gm, nd)
        end
    end
    return gm
end


function expr_merge(gs::Vararg{ExGraph})
    return reduce(expr_merge, gs)
end


function expr_merge(exs::Vararg{Expr})
    ctx = to_context(Dict())
    gs = [ExGraph(ex; ctx=ctx) for ex in exs]
    gm = expr_merge(gs...)
    block = to_iexpr(gm)
    res_vars = [g[end].var for g in gs]
    push!(block.args, Expr(:tuple, res_vars...))
    return block
end
