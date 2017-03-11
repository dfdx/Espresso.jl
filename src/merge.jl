
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
    gm = ExGraph(:(no + expr), false)
    # find out what vars in g2 need to be renamed
    g1_vars = Set(nd.var for nd in g1.tape)
    g2_vars = Set(nd.var for nd in g2.tape)
    need_renaming = Symbol[]
    for nd in g2.tape
        if haskey(g1, nd.var) && expr(g1[nd.var]) != expr(nd)
            push!(need_renaming, nd.var)
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
        if !haskey(gm, nd.var)           
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
    block = to_iexpr(gm)
    res_vars = [g[end].var for g in gs]
    push!(block.args, Expr(:tuple, res_vars...))
    return block
end
