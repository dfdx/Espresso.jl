
function expr_merge(g1::ExGraph, g2::ExGraph)
    gm = ExGraph(:(no + expr), false)
    for nd in g1.tape
        addnode!(gm, nd)
    end
    for nd in g2.tape
        if haskey(gm, nd.var)
            if expr(gm[nd.var]) != expr(nd)
                error("Can't merge expression graphs: " *
                      "in g1 $(to_iexpr(g1[nd.var])), but in g2 $(to_iexpr(nd))")
            end
        else
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
