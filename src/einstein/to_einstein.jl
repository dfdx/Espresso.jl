
# from vectorized to Einstein notation

const TO_EINSTEIN_RULES =
    OrderedDict((:sum, [0]) => [(:(sum(X)), :(X[] * I[]))],
                (:sum, [1]) => [(:(sum(X)), :(X[i] * I[i]))],
                (:sum, [2]) => [(:(sum(X)), :(X[i,j] * I[i,j]))],
                (:sum, [2, 0]) => [(:(sum(X, 1)), :(I[i] * X[i,j])),
                                   (:(sum(X, 2)), :(X[i,j] * I[j]))],
                (:*, [0, 0]) => [(:(X * Y), :(X[] * Y[]))],
                (:*, [1, 1]) => [(:(X * Y), :(X[i] * Y[i]))],
                (:*, [2, 1]) => [(:(X * Y), :(X[i,k] * Y[k]))],
                (:*, [1, 2]) => [(:(X * Y), :(X[k] * Y[k,j]))],
                (:*, [2, 2]) => [(:(X * Y), :(X[i,j] * Y[k,j]))])

function to_einstein(ex::Expr; ctx=Dict(), inputs...)
    g = ExGraph(ex; ctx=to_context(ctx), inputs...)
    forward_pass(g)
    res = :(begin end)
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            push!(res.args, to_einstein(g, nd))
        end
    end
    return res
end


function to_einstein(g::ExGraph, nd::ExNode{:constant})
    return to_expr(nd)
end


function to_einstein(g::ExGraph, nd::ExNode{:call})
    ex = expand_const_1(g, nd)
    op = ex.args[1]
    dep_dims = [ndims(g[dep].val) for dep in dependencies(nd) if haskey(g, dep)]
    if haskey(TO_EINSTEIN_RULES, (op, dep_dims))
        rules = TO_EINSTEIN_RULES[(op, dep_dims)]
        for (pat, subex) in rules
            matched = tryrewrite(ex, pat, subex; phs=TDIFF_PHS)
            if !isnull(matched)
                new_ex = get(matched)
                varidxs = forall_indices(new_ex)
                return Expr(:(=), maybe_indexed(nd.var, varidxs), new_ex)
            end
        end
        # if nothing matched, throw an error
        error("Don't know how to convert expression $(to_expr(nd)) to " *
              "Einstein notation")
    ## elseif all(dep_dims .== dep_dims[1])
    ##     # treat as elementwise
    ##     idxs = IDX_NAMES[1:length(dep_dims[1])]
    ##     ivar = Expr(:ref, nd.var, idxs...)
    ##     ideps = [Expr(:ref, dep, idxs...) for dep in dependencies(nd)]
    ##     icall = Expr(:call, op, ideps...)
    ##     return Expr(:(=), ivar, icall)
    else
        depidxs = [IDX_NAMES[1:dims] for dims in dep_dims]
        ideps = [maybe_indexed(dep, idxs)
                 for (dep, idxs) in zip(dependencies(nd), depidxs)]
        icall = Expr(:call, op, ideps...)
        varidxs = forall_indices(icall)
        ivar = maybe_indexed(nd.var, varidxs)
        return Expr(:(=), ivar, icall)
    end
end

function to_einstein(g::ExGraph, nd::ExNode{:(=)})
    dep = dependencies(nd)[1]
    varidxs = g[dep].idxs[1]
    lhs = Expr(:ref, nd.var, varidxs...)
    rhs = Expr(:ref, dep, varidxs...)
    return Expr(:(=), lhs, rhs)
end
