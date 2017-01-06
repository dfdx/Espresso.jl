
# from vectorized to Einstein notation

# TODO: add LHS to patterns
# TODO: fix transpose
# TODO: maybe remove pseudoone

const TO_EINSTEIN_RULES =
    OrderedDict((:sum, [0]) => [:(Z = sum(X)) => :(Z = X)],
                (:sum, [1]) => [:(Z = sum(X)) => :(Z = X[i])],
                (:sum, [2]) => [:(Z = sum(X)) => :(Z = X[i,j])],
                (:sum, [2, 0]) => [:(Z = sum(X, 1)) => :(Z[j] = X[i,j]),
                                   :(Z = sum(X, 2)) => :(Z[i] = X[i,j])],
                (:*, [0, 0]) => [:(Z = X * Y) => :(Z = X * Y)],
                # (:*, [1, 1]) => [(:(X * Y), :(X[i] * Y[i]))], -- invalid?
                (:*, [2, 1]) => [:(Z = X * Y) => :(Z[i] = X[i,k] * Y[k])],
                (:*, [1, 2]) => [:(Z = X * Y) => :(Z[j] = X[k] * Y[k,j])],
                (:*, [2, 2]) => [:(Z = X * Y) => :(Z[i,j] = X[i,j] * Y[k,j])],
                (:transpose, [1]) => [:(Z = transpose(X)) => :(Z[i] = X[i])],
                (:transpose, [2]) => [:(Z = transpose(X)) => :(Z[j,i] = X[i,j])])

function to_einstein(ex::Expr; ctx=Dict(), inputs...)
    g = ExGraph(ex; ctx=to_context(ctx), inputs...)
    evaluate!(g, g.tape[end].var)
    propagate_size!(g)
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
    op = ex.args[2].args[1]
    dep_dims = [ndims(g[dep].val) for dep in dependencies(nd) if haskey(g, dep)]
    if haskey(TO_EINSTEIN_RULES, (op, dep_dims))
        rules = TO_EINSTEIN_RULES[(op, dep_dims)]
        for (pat, subex) in rules
            matched = tryrewrite(ex, pat, subex; phs=FROM_EIN_PHS)
            if !isnull(matched)
                new_ex = get(matched)
                return new_ex
                # varidxs = forall_indices(new_ex)
                # return Expr(:(=), maybe_indexed(nd.var, varidxs), new_ex)
            end
        end
        # if nothing matched, throw an error
        error("Don't know how to convert expression $(to_expr(nd)) to " *
              "Einstein notation")
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
