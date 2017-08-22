
# to_einstein.jl - from vectorized to Einstein notation

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
                (:transpose, [2]) => [:(Z = transpose(X)) => :(Z[j,i] = X[i,j])],
                (:conv2, [2, 2]) => [:(Z = conv2(X, W)) => :(Z[i,j] = X[i+m-1, j+n-1] * W[m,n])])


"""
to_einstein(ex::Expr; ctx=Dict(), inputs...)

Transform expression `ex` to Einstein indexing notation.
"""
function to_einstein(ex::Expr; ctx=Dict(), inputs...)
    g = ExGraph(ex; ctx=to_context(ctx), inputs...)
    evaluate!(g)
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
    dep_dims = [ndims(getvalue(g[dep])) for dep in dependencies(nd) if haskey(g, dep)]
    if op in SPECIAL_FUNCS
        rhs = getexpr(nd)
        vnames = find_vars(rhs)
        vars = [:($vname[:]) for vname in vnames]
        new_rhs = subs(rhs, Dict(zip(vnames, vars)))
        new_lhs = with_indices(varname(nd), ndims(getvalue(nd)))
        return :($new_lhs = $new_rhs)
    elseif haskey(TO_EINSTEIN_RULES, (op, dep_dims))
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
    # transforming `f.(x)` to `f.(x[i])` is preferable than to `f(x[i])`,
    # but Einsum currectly doesn't support broadcasting, so have
    # to go with the second option
    #   iex = Expr(:., op, Expr(:tuple, deps...))
    iex = Expr(:call, op, deps...)
    vidxs = forall_indices(iex)
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


function to_einstein(g::ExGraph, nd::ExNode{:tuple})
    depnames = dependencies(nd)
    dep_dims = [ndims(getvalue(g[dep])) for dep in depnames if haskey(g, dep)]
    depidxs = [IDX_NAMES[1:dims] for dims in dep_dims]
    deps = [make_indexed(depname, idxs)
            for (depname, idxs) in zip(depnames, depidxs)]
    tuple_ex = Expr(:tuple, deps...)
    var = Expr(:ref, varname(nd), :)
    return Expr(:(=), var, tuple_ex)
end
