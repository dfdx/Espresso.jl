
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

function to_einstein(ex::Expr; xs...)
    g = ExGraph(ex; xs...)
    forward_pass(g)
    res = :(begin end)
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            push!(res.args, to_einstein(g, nd))
        end
    end
    return res
end


function expand_const_1(g::ExGraph, nd::ExNode{:call})
    st = Dict()
    for dep in dependencies(nd)
        if haskey(g, dep) && isa(g[dep], ExNode{:constant})
            st[dep] = g[dep].val
        end
    end
    return subs(expr(nd), st)
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


# from Einstein to vectorized notation

const FROM_EINSTEIN_RULES =
    OrderedDict(:(Z = X[i] * I[i]) => :(Z = sum(X)),
                :(Z = I[i] * X[i]) => :(Z = sum(X)),
                :(Z = X[i,j] * I[i,j]) => :(Z = sum(X)),
                :(Z = I[i,j] * X[i,j]) => :(Z = sum(X)),
                :(Z[j] = I[i] * X[i,j]) => :(Z = sum(X,1)'),
                :(Z[i] = I[j] * X[i,j]) => :(Z = sum(X,2)),
                :(Z[i] = X[i,j] * I[j]) => :(Z = sum(X,2)),
                :(Z[j] = X[i,j] * I[i]) => :(Z = sum(X,1)'),
                # inner and outer product
                :(Z = X[i] * Y[i]) => :(Z = X'Y),   # or sum(X[i] * Y[i])?
                :(Z[i,j] = X[i] * Y[j]) => :(Z = X * Y'),
                # matrix-by-vector
                :(Z[j] = X[i] * Y[i,j]) => :(Z = Y' * X),
                :(Z[i] = X[j] * Y[i,j]) => :(Z = Y * X),
                :(Z[i] = X[i,j] * Y[j]) => :(Z = X * Y),
                :(Z[j] = X[i,j] * Y[i]) => :(Z = X' * Y),
                # matrix-by-matrix
                :(Z[i,j] = X[i,k] * Y[k,j]) => :(Z = X * Y),
                :(Z[i,j] = Y[k,j] * X[i,k]) => :(Z = X * Y),
                # repmat
                :(Z[i,j] = X[j]) => :(Z = repmat(X', size(Z, 1))),
                :(Z[i,j] = X[i]) => :(Z = repmat(X, 1, size(Z, 2))),
                # assignment
                :(Z = X) => :(Z = X),
                :(Z[i] = X[i]) => :(Z = X),
                :(Z[i,j] = X[i,j]) => :(Z = X),
                :(Z[i,j,k] = X[i,j,k]) => :(Z = X))


function from_einstein(ex::Expr)
    g = ExGraph(ex)
    res = :(begin end)
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            push!(res.args, from_einstein(nd))
        end
    end
    return res
end

# from_einstein(nd::ExNode{:(=)}) = to_expr(nd)
from_einstein(nd::ExNode{:input}) = expr(nd)
from_einstein(nd::ExNode{:constant}) = value(nd)

function from_einstein(nd::Union{ExNode{:call}, ExNode{:(=)}})
    ex = to_iexpr(nd)    
    for (pat, rpat) in FROM_EINSTEIN_RULES
        if !isnull(matchex(pat, ex; phs=TDIFF_PHS))   # consider tryrewrite
            rex = rewrite(ex, pat, rpat; phs=TDIFF_PHS)
            return rex
        end
    end
    error("No pattern to transform from Einstein notation, expression: $ex")    
end
