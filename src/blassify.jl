
const BLASSIFY_PHS = Set([:X, :Y, :Z])

const BLASSIFY_RULES = [
    [Matrix, Matrix] => :(Z = X * Y) => :(A_mul_B!(Z, X, Y)),
    [Array] => :(Z = _f.(X)) => :(Z .= _f(X)),
    [Vector, Vector] => :(Z = _f.(X, Y)) => :(Z .= _f(X, Y)),
    [Matrix, Matrix] => :(Z = _f.(X, Y)) => :(Z .= _f(X, Y)),

]



function blassify(ex::Expr; inputs...)
    g = ExGraph(ex; inputs...)
    # TODO: fuse broadcast chains
    block = Expr(:block)
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            subex = blassify(g, nd)
            push!(block.args, subex)
        end
    end
    return block
end


function blassify(g::ExGraph, nd::ExNode{:bcast})
    ex = to_expr(nd)
    ex.head =  :.=
    return ex
end


function blassify(g::ExGraph, nd::Union{ExNode{:call}, ExNode{:(=)},
                                        ExNode{:opaque}, ExNode{:constant}})
    ex = to_expr(nd)
    if is_bcast(ex.args[2])
        # special case: broadcasting
        new_ex = copy(ex)
        ex.head =  :.=
        return ex
    else
        # if previous check doesn't succeed, try rules
        dep_types = [typeof(getvalue(g[dep])) for dep in dependencies(nd) if haskey(g, dep)]
        for (pat_dep_types, (pat, rpat)) in BLASSIFY_RULES
            if all(t <: pt for (t, pt) in zip(dep_types, pat_dep_types))
                rex = tryrewrite(ex, pat, rpat; phs=BLASSIFY_PHS)
                if !isnull(rex)
                    return get(rex)
                end
            end
        end
        error("Don't know how to blassify $nd of types $dep_types")
    end
end
