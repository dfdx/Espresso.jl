
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
    forward_pass(g, ex)
    res = :(begin end)
    for nd in g.tape
        if !isa(nd, ExNode{:input}) && !isa(nd, ExNode{:constant})
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
                return Expr(:(=), Expr(:ref, nd.var, varidxs...), new_ex)
            end
        end
        # if nothing matched, throw an error
        error("Don't know how to convert expression $(to_expr(nd)) to " *
              "Einstein notation")
    elseif all(dep_dims .== dep_dims[1])
        # treat as elementwise
        idxs = IDX_NAMES[1:length(dep_dims[1])]
        ivar = Expr(:ref, nd.var, idxs...)
        ideps = [Expr(:ref, dep, idxs...) for dep in dependencies(nd)]
        icall = Expr(:call, op, ideps...)
        return Expr(:(=), ivar, icall)
    else
        error("Don't know how to convert expression $(to_expr(nd)) to " *
              "Einstein notation")
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
    OrderedDict(:(X[i] * I[i]) => :(sum(X)),
                :(I[i] * X[i]) => :(sum(X)),
                :(X[i,j] * I[i,j]) => :(sum(X)),
                :(I[i,j] * X[i,j]) => :(sum(X)),
                :(I[i] * X[i,j]) => :(sum(X,1)'),
                :(I[j] * X[i,j]) => :(sum(X,2)),
                :(X[i,j] * I[j]) => :(sum(X,2)),
                :(X[i,j] * I[i]) => :(sum(X,1)'),
                # inner and outer product
                :(X[i] * Y[i]) => :(X'Y),   # or sum(X[i] * Y[i])?
                :(X[i] * Y[j]) => :(X * Y'),
                # matrix-by-vector
                :(X[i] * Y[i,j]) => :(Y' * X),
                :(X[j] * Y[i,j]) => :(Y * X),
                :(X[i,j] * Y[j]) => :(X * Y),
                :(X[i,j] * Y[i]) => :(X' * Y),
                # matrix-by-matrix
                :(X[i,k] * Y[k,j]) => :(X * Y),
                :(Y[k,j] * X[i,k]) => :(X * Y))


function from_einstein(ex::Expr; inputs...)
    g = ExGraph(ex; inputs...)    
    res = :(begin end)
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            push!(res.args, from_einstein(nd))
        end
    end
    return res
end

from_einstein(nd::ExNode{:(=)}) = to_expr(nd)
from_einstein(nd::ExNode{:input}) = expr(nd)
from_einstein(nd::ExNode{:constant}) = value(nd)

function from_einstein(nd::ExNode{:call})
    ex = iexpr(nd)
    if ex.args[1]  == :*
        for (pat, rpat) in FROM_EINSTEIN_RULES
            if !isnull(matchex(pat, ex; phs=TDIFF_PHS))   # consider tryrewrite
                rex = rewrite(ex, pat, rpat; phs=TDIFF_PHS)
                return :($(nd.var) = $rex)
            end
        end
        error("No pattern to transform from Einstein notation, expression: $ex")
    else
        return to_expr(nd)
    end
end

