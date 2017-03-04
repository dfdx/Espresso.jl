
# from Einstein to vectorized notation

const FROM_EIN_PHS = [:A, :B, :C, :X, :Y, :V, :W, :Z,
                      :i, :j, :k, :l, :m, :n, :p, :q, :r, :s, :t]

const FROM_EINSTEIN_RULES =
    OrderedDict(:(Z[j] = I[i] * X[i,j]) => :(Z = sum(X,1)'),
                :(Z[i] = I[j] * X[i,j]) => :(Z = sum(X,2)),
                :(Z[i] = X[i,j] * I[j]) => :(Z = sum(X,2)),
                :(Z[j] = X[i,j] * I[i]) => :(Z = sum(X,1)'),
                :(Z[i] = X[i,j]) => :(Z = sum(X,1)'),
                :(Z = X[i] * I[i]) => :(Z = sum(X)),
                :(Z = I[i] * X[i]) => :(Z = sum(X)),
                :(Z = X[i,j] * I[i,j]) => :(Z = sum(X)),
                :(Z = I[i,j] * X[i,j]) => :(Z = sum(X)),
                # no-pseudoone summation
                :(Z[i] = X[i,j]) => :(Z = sum(X,2)),
                :(Z[j] = X[i,j]) => :(Z = sum(X,1)'),
                :(Z = X[i]) => :(Z = sum(X)),
                :(Z = X[i,j]) => :(Z = sum(X)),
                :(Z = X[i,j,k]) => :(Z = sum(X)),
                # assignment
                # :(Z = X) => :(Z = X),  # don't use, matches everything
                :(Z[i] = X[i]) => :(Z = X),
                :(Z[i,j] = X[i,j]) => :(Z = X),
                :(Z[i,j,k] = X[i,j,k]) => :(Z = X),
                # inner and outer product
                :(Z[i,j] = X[i] * Y[j]) => :(Z = X * Y'),
                :(Z = X[i] * Y[i]) => :(Z = X'Y),   # or sum(X[i] * Y[i])?
                :(Z[i,j] = X[i] .* Y[j]) => :(Z = X * Y'),
                :(Z = X[i] .* Y[i]) => :(Z = X'Y),   # or sum(X[i] * Y[i])?
                # matrix-by-vector
                :(Z[j] = X[i] * Y[i,j]) => :(Z = Y' * X),
                :(Z[i] = X[j] * Y[i,j]) => :(Z = Y * X),
                :(Z[i] = X[i,j] * Y[j]) => :(Z = X * Y),
                :(Z[j] = X[i,j] * Y[i]) => :(Z = X' * Y),
                :(Z[j] = X[i] .* Y[i,j]) => :(Z = Y' * X),
                :(Z[i] = X[j] .* Y[i,j]) => :(Z = Y * X),
                :(Z[i] = X[i,j] .* Y[j]) => :(Z = X * Y),
                :(Z[j] = X[i,j] .* Y[i]) => :(Z = X' * Y),
                # matrix-by-matrix
                :(Z[i,j] = X[i,k] * Y[k,j]) => :(Z = X * Y),
                :(Z[i,j] = Y[k,j] * X[i,k]) => :(Z = X * Y),
                :(Z[i,j] = X[i,k] .* Y[k,j]) => :(Z = X * Y),
                :(Z[i,j] = Y[k,j] .* X[i,k]) => :(Z = X * Y),
                :(Z[i,j] = Y[i,j] .* X[j,i]) => :(Z = X * Y'),
                # repmat
                :(Z[i,j] = X[j]) => :(Z = repmat(X', size__(Z)[1])),
                :(Z[i,j] = X[i]) => :(Z = repmat(X, 1, size__(Z)[2])),
                # eye
                :(Z[i,j] = 1 * (i == j)) => :(eye(size__(Z))[1]),
                # constant
                :(Z[i] = X) => :(Z = ones(size__(Z)) * X),
                # special .*
                :(Z[i,j] = X[j] .+ Y[i,j]) => :(Z = X' .+ Y))
                # broadcasting
                # :(Z[i] = _op(_a, X[i])) => :(Z = _op(_a, X)),
                # :(Z[i,j] = _op(_a, X[i,j])) => :(Z = _op(_a, X)),
                # :(Z[i,j,k] = _op(_a, X[i,j,k])) => :(Z = _op(_a, X)),
                # :(Z[i] = _op(X[i], _a)) => :(Z = _op(X, _a)),
                # :(Z[i,j] = _op(X[i,j], _a)) => :(Z = _op(X, _a)),
                # :(Z[i,j,k] = _op(X[i,j,k], _a)) => :(Z = _op(X, _a)),
                # :(Z[i,j] = _op(X[i], Y[i,j])) => :(Z = _op(X, Y)),
                # :(Z[i,j] = _op(X[i,j], Y[i])) => :(Z = _op(X, Y)),
                # :(Z[i,j] = _op(X[j], Y[i,j])) => :(Z = _op(X', Y)),
                # :(Z[i,j] = _op(X[i,j], Y[j])) => :(Z = _op(X', Y)),
                # # elementwise operations (move to special case?)
                # :(Z = _op(X)) => :(Z = _op(X)),
                # :(Z[i] = _op(X[i])) => :(Z = _op(X)),
                # :(Z[i,j] = _op(X[i,j])) => :(Z = _op(X)),
                # :(Z[i,j,k] = _op(X[i,j,k])) => :(Z = _op(X)),
                # :(Z = _op(X,Y)) => :(Z = _op(X,Y)),
                # :(Z[i] = _op(X[i], Y[i])) => :(Z = _op(X,Y)),
                # :(Z[i,j] = _op(X[i,j], Y[i,j])) => :(Z = _op(X,Y)),
                # :(Z[i,j,k] = _op(X[i,j,k], Y[i,j,k])) => :(Z = _op(X,Y)),
                # :(Z[i] = _mod._op(X[i])) => :(Z = _mod._op(X)),
                # :(Z[i,j] = _mod._op(X[i,j])) => :(Z = _mod._op(X)),
                # :(Z[i,j,k] = _mod._op(X[i,j,k])) => :(Z = _mod._op(X)))


function subs_size(ex::Expr, sizes::Dict)
    # TODO: check expressions like size(W, 1)
    size_exs = findex(:(size__(_)), ex)
    st = Dict{Any,Any}()
    for size_ex in size_exs
        var, idxs = parse_indexed(size_ex.args[2])
        subsex = @get(sizes, var, error("Can't find size for $var in $ex"))
        st[size_ex] = subsex
    end
    return subs(ex, st)
end

subs_size(x, sizes::Dict) = x


function from_einstein(ex::Expr; ctx=Dict(), inputs...)
    g = ExGraph(ex; ctx=ctx, inputs...)
    sizes = @get(g.ctx, :sizes, Dict())
    res = :(begin end)
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            vex = from_einstein(g, nd)
            push!(res.args, simplify(subs_size(vex, sizes)))
        end
    end
    return res
end

# from_einstein(nd::ExNode{:(=)}) = to_expr(nd)
from_einstein(g::ExGraph, nd::ExNode{:input}) = expr(nd)
from_einstein(g::ExGraph, nd::ExNode{:constant}) = to_expr(nd)


function from_einstein(g::ExGraph, nd::Union{ExNode{:call}, ExNode{:(=)}})
    ex = to_iexpr(nd)
    for (pat, rpat) in FROM_EINSTEIN_RULES
        # consider tryrewrite
        if !isnull(matchex(pat, ex; phs=FROM_EIN_PHS, allow_ex=false))
            rex = rewrite(ex, pat, rpat; phs=FROM_EIN_PHS)
            return rex
        end
    end
    # if no patterns found, try broadcasting
    all_idxs = call_indices(to_iexpr(nd))
    longest_idx = longest_index(all_idxs)
    is_bcast = (all(idx -> idx == longest_idx || isempty(idx), all_idxs))
    is_bcast_old = in(ex.args[2].args[1], Set([:.*, :.+, :.-, :./, :.^]))
    if is_bcast_old
        # nearly deprecated syntax, but still actively used in 0.6
        call = Expr(:call, expr(nd).args[1], dependencies(nd)...)
        return Expr(:(=), nd.var, call)
    elseif is_bcast
        # TODO handle ExNode{:(=)} too
        bcast_call = Expr(:., expr(nd).args[1], Expr(:tuple, dependencies(nd)...))
        return Expr(:(=), nd.var, bcast_call)
    else
        error("Neither pattern found, nor broadcasting is applicable when transformaing from" *
              "Einstein notation, expression: $ex")
    end
end


function from_einstein(g::ExGraph, nd::ExNode{:bcast})
    ex = to_iexpr(nd)
    ivars = indexed_vars(ex)
    st = Dict(ivar => ivar.args[1] for ivar in ivars)
    return subs(ex, st)
end
