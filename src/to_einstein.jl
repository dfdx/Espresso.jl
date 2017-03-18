
# to_einstein.jl - from vectorized to Einstein notation

const IDX_NAMES = [:i, :j, :k, :l, :m, :n, :p, :q, :r, :s]


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
                (:*, [2, 2]) => [:(Z = X * Y) => :(Z[i,j] = X[i,k] * Y[k,j])],
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
    # ex = expand_const_1(g, nd)
    ex = to_expr(nd)
    op = ex.args[2].args[1]
    dep_dims = [ndims(value(g[dep])) for dep in dependencies(nd) if haskey(g, dep)]
    if haskey(TO_EINSTEIN_RULES, (op, dep_dims))
        rules = TO_EINSTEIN_RULES[(op, dep_dims)]
        for (pat, subs_ex) in rules
            matched = tryrewrite(ex, pat, subs_ex; phs=FROM_EIN_PHS)
            if !isnull(matched)
                new_ex = get(matched)
                return new_ex         
            end
        end
        # if nothing matched, throw an error
        error("Don't know how to convert expression $(to_expr(nd)) to " *
              "Einstein notation")
    else
        depidxs = [IDX_NAMES[1:dims] for dims in dep_dims]
        deps = [make_indexed(depname, idxs)
                 for (depname, idxs) in zip(dependencies(nd), depidxs)]
        callex = Expr(:call, op, deps...)
        vidxs = forall_indices(callex)
        var = make_indexed(varname(nd), vidxs)
        return Expr(:(=), var, callex)
    end
end


function to_einstein(g::ExGraph, nd::ExNode{:bcast})
    # ex = expand_const_1(g, nd)
    ex = to_expr(nd)
    op = ex.args[2].args[1]
    dep_dims = [ndims(g[dep].val) for dep in dependencies(nd) if haskey(g, dep)]    
    depidxs = [IDX_NAMES[1:dims] for dims in dep_dims]
    deps = [make_indexed(depname, idxs)
            for (depname, idxs) in zip(dependencies(nd), depidxs)]
    iex = Expr(:., op, Expr(:tuple, deps...))
    vidxs = forall_indices(icall)
    var = make_indexed(varname(nd), vidxs)
    return Expr(:(=), var, iex)
end


function to_einstein(g::ExGraph, nd::ExNode{:(=)})
    depname = dependencies(nd)[1]
    vidxs = varidxs(g[depname])
    lhs = make_indexed(varname(nd), vidxs)
    rhs = make_indexed(dep, vidxs)
    return Expr(:(=), lhs, rhs)
end
