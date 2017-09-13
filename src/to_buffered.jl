
# to_buffered.jl - transform EinGraph to buffered/in-place operations

using DataStructures

const TO_BUFFERED_PHS = [:A, :B, :C, :X, :Y, :V, :W, :Z,
                      :i, :j, :k, :l, :m, :n, :p, :q, :r, :s, :t]

const TO_BUFFERED_CALL_RULES =
    OrderedDict(# sum_n
                :(Z[i,j] = sum_1(X[:,j])) => :(Z .= sum(X, 1)),
                :(Z[i,j] = Espresso.sum_1(X[:,j])) => :(Z .= sum(X, 1)),
                :(Z[i,j] = sum_2(X[i,:])) => :(Z .= sum(X, 2)),
                :(Z[i,j] = Espresso.sum_2(X[i,:])) => :(Z .= sum(X, 2)),
                # sum_n + sum
                :(Z = sum_1(X[:,j])) => :(Z .= sum(sum(X, 1))),
                :(Z = Espresso.sum_1(X[:,j])) => :(Z .= sum(sum(X, 1))),
                :(Z = sum_2(X[i,:])) => :(Z .= sum(sum(X, 2))),
                :(Z = Espresso.sum_2(X[i,:])) => :(Z .= sum(sum(X, 2))),
                # inner and outer product
                :(Z[i,j] = X[i] * Y[j]) => :(A_mul_Bt!(Z, X, Y)),
                # :(Z = X[i] * Y[i]) => :(Z = X'Y),
                :(Z[i,j] = X[i] .* Y[j]) => :(A_mul_Bt!(Z, X, Y)),
                # :(Z = X[i] .* Y[i]) => :(Z = X'Y),
                # matrix-by-vector
                # :(Z[j] = X[i] * Y[i,j]) => :(Z = Y' * X),
                # :(Z[i] = X[j] * Y[i,j]) => :(Z = Y * X),
                :(Z[i] = X[i,j] * Y[j]) => :(A_mul_B!(Z, X, Y)),
                # :(Z = X[i,j] * Y[j]) => :(Z = sum(X * Y)),
                :(Z[j] = X[i,j] * Y[i]) => :(At_mul_B!(Z, X, Y)),
                # :(Z = X[i,j] * Y[i]) => :(Z = sum(X' * Y)),
                :(Z[j] = X[i] .* Y[i,j]) => :(At_mul_B!(Z, Y, X)),
                # :(Z[i] = X[j] .* Y[i,j]) => :(Z = Y * X),
                # :(Z[i] = X[i,j] .* Y[j]) => :(Z = X * Y),
                # :(Z[j] = X[i,j] .* Y[i]) => :(Z = X' * Y),
                # :(Z[i,j] = X[i,j] .* Y[i]) => :(Z = X .* Y),
                # :(Z[i,j] = X[i,j] .* Y[j]) => :(Z = X .* Y'),
                # matrix-by-matrix
                :(Z[i,j] = X[i,k] * Y[k,j]) => :(A_mul_B!(Z, X, Y)),
                :(Z[i,j] = Y[k,j] * X[i,k]) => :(A_mul_B!(Z, X, Y)),
                :(Z[i,j] = X[i,k] .* Y[k,j]) => :(A_mul_B!(Z, X, Y)),
                :(Z[i,j] = Y[k,j] .* X[i,k]) => :(A_mul_B!(Z, X, Y)),
                :(Z[i,j] = Y[i,j] .* X[j,i]) => :(A_mul_Bt!(Z, X, Y)),
                # matrix-by-matrix: 3-index rule
                :(Z[i,j] = X[i,k] .* Y[j,k]) => :(A_mul_Bt!(Z, X, Y)),
                :(Z[i,j] = X[k,i] .* Y[k,j]) => :(At_mul_B!(Z, X, Y)),
                :(Z[j,i] = X[i,k] .* Y[j,k]) => :(A_mul_Bt!(Z, Y, X)),  # same transposed
                :(Z[j,i] = X[k,i] .* Y[k,j]) => :(At_mul_B!(Z, Y, X)),  # same transposed
                :(Z[i] = X[j, k] .* Y[j, i]) => :(Z .= squeeze(sum(X' * Y, 1)', 2)),
                :(Z[k] = X[j, k] .* Y[j, i]) => :(Z .= squeeze(sum(X' * Y, 2), 2)),
                # other 3-index rules
                :(Z[i,j] = X[j,k] .* Y) => :(Z .= Y .* sum(X,2)'),
                :(Z[i,j] = Y .* X[j,k]) => :(Z .= Y .* sum(X,2)'),
                :(Z[i,j] = X[k,j] .* Y) => :(Z .= Y .* sum(X, 1)),
                :(Z[i,j] = Y .* X[k,j]) => :(Z .= Y .* sum(X, 1)),
                :(Z[i,j] = -X[k,i]) => :(Z .= sum(X, 1)'),
                :(Z[i,j] = -X[k,j]) => :(Z .= -sum(X, 1)),
                :(Z[i,j] = -X[i,k]) => :(Z .= -sum(X, 2)),
                :(Z[i,j] = -X[j,k]) => :(Z .= -sum(X, 2)'),
                # special .+ and .*
                :(Z[i,j] = X[i,j] .+ Y[i]) => :(Z .= X .+ Y),
                :(Z[i,j] = X[i] .+ Y[i,j]) => :(Z .= X .+ Y),
                :(Z[i,j] = X[i,j] .* Y[i]) => :(Z .= X .* Y),
                :(Z[i,j] = X[i] .* Y[i,j]) => :(Z .= X .* Y),
                # :(Z[i,j] = X[j] .+ Y[i,j]) => :(Z .= X' .+ Y),   # can it happen
                # :(Z[i,j] = X .* Y[j]) => :(Z = repmat((X .* Y)', size__(Z)[1])),
                # :(Z[j] = X .* Y[i,j]) => :(Z = X .* squeeze(sum(Y,1),1)),
                # # eye
                # :(Z[i,j] = 1 * (i == j)) => :(Z = eye(size__(Z))[1]),
                # # –> ∑ₖxᵢyⱼₖ == xᵢ∑ₖyⱼₖ   # TODO: seems incorrect, see 2-level rules
                # # :(Z[i,j] = X[i] .* Y[j,k]) => :(Z = X .* squeeze(sum(Y,2),2))
                # # broadcasting
                :(Z = _f(X)) => :(Z = _f(X)),
                :(Z = _f(X, Y)) => :(Z = _f(X, Y)),
                :(Z[i...] = _f(X[i...])) => :(Z .= _f.(X)),
                :(Z[i...] = _f(X[i...], Y[i...])) => :(Z .= _f.(X, Y)),
                :(Z[i...] = _f(X[i...], Y)) => :(Z .= _f.(X, Y)),
                :(Z[i...] = _f(X, Y[i...])) => :(Z .= _f.(X, Y)),
                # broadcasting with module
                :(Z = _M._f(X)) => :(Z = _M._f(X)),
                :(Z = _M._f(X, Y)) => :(Z = _M._f(X, Y)),
                :(Z[i...] = _M._f(X[i...])) => :(Z .= _M._f.(X)),
                :(Z[i...] = _M._f(X[i...], Y[i...])) => :(Z .= _M._f.(X, Y)),
                :(Z[i...] = _M._f(X[i...], Y)) => :(Z .= _M._f.(X, Y)),
                :(Z[i...] = _M._f(X, Y[i...])) => :(Z .= _M._f.(X, Y)),
                # broadcasting + sum
                :(Z = _f(X[i...])) => :(Z = sum(_f.(X))),
                :(Z[i] = _f(X[i,j])) => :(Z = squeeze(sum(_f.(X),2),2)),
                :(Z[j] = _f(X[i,j])) => :(Z = squeeze(sum(_f.(X),1),1)),
                :(Z[i] = _f(X[i,j], Y[i,j])) => :(Z = squeeze(sum(_f.(X, Y),2),2)),
                :(Z[j] = _f(X[i,j])) => :(Z = squeeze(sum(_f.(X),1),1)),
                :(Z[j] = _f(X[i,j], Y[i,j])) => :(Z = squeeze(sum(_f.(X, Y),1),1)),
                :(Z = _f(X[i...], Y)) => :(Z = sum(_f.(X, Y))),
                :(Z = _f(X, Y[i...])) => :(Z = sum(_f.(X, Y))),

                # causing problems?
                # :(Z = _f(X[i...], Y[i...])) => :(Z = sum(_f.(X, Y))),
                # :(Z[i] = _f(X[i,j], Y[i,j])) => :(Z .= sum(_f(X, Y), 2)),
                # :(Z[j] = _f(X[i,j], Y[i,j])) => :(Z .= sum(_f(X, Y), 1)),
                # :(Z[i] = _M._f(X[i,j], Y[i,j])) => :(Z .= sum(_M._f(X, Y), 2)),
                # :(Z[j] = _M._f(X[i,j], Y[i,j])) => :(Z .= sum(_M._f(X, Y), 1)),

                # :(Z = _f(X[i,j], Y[i,j])) => :(Z = sum(_f(X, Y))),
                # broadcasting + sum with module
                :(Z = _M._f(X[i...])) => :(Z = sum(_M._f.(X))),
                :(Z[i] = _M._f(X[i,j])) => :(Z = squeeze(sum(_M._f.(X),2),2)),
                :(Z[j] = _M._f(X[i,j])) => :(Z = squeeze(sum(_M._f.(X),1),1)),
                :(Z[i] = _M._f(X[i,j], Y[i,j])) => :(Z = squeeze(sum(_M._f.(X, Y),2),2)),
                :(Z[j] = _M._f(X[i,j])) => :(Z = squeeze(sum(_M._f.(X),1),1)),
                :(Z[j] = _M._f(X[i,j], Y[i,j])) => :(Z = squeeze(sum(_M._f.(X, Y),1),1)),
                :(Z = _M._f(X[i...], Y)) => :(Z = sum(_M._f.(X, Y))),
                :(Z = _M._f(X, Y[i...])) => :(Z = sum(_M._f.(X, Y))),
                :(Z = _M._f(X[i...], Y[i...])) => :(Z = sum(_M._f.(X, Y))),
                # :(Z = _M._f(X[i,j], Y[i,j])) => :(Z = sum(_M._f(X, Y))),
                # # constants
                # :(Z[i...] = _f(X, Y)) => :(Z = ones(size__(Z)) .* _f(X, Y)),
                # # convolution
                # # TODO: test conv rules
                # # direct conv
                # :(Z[i,j] = X[i+m-1, j+n-1] * W[m,n]) => :(Z = conv2(X, W)),
                # :(Z = X[i+m-1, j+n-1] * W[m,n]) => :(Z = sum(conv2(X, W))),
                # # reverse conv
                # :(Z[i,j] = X[p-i+1, q-j+1] * Y[p, q]) => :(Z = conv2(X, flip(X))),
                # :(Z = X[p-i+1, q-j+1] * Y[p, q]) => :(Z = sum(conv2(X, flip(X)))),
                # # conv over ones(...)
                # :(Z[m,n] = X[i+m-1, j+n-1]) => :(Z = conv2(X, ones(size__(Z)))),
                # :(Z[p,q] = X[p-i+1, q-j+1]) => :(Z = conv2(ones(size__(Z)), flip(X))),
                )


const TO_BUFFERED_ASSIGN_RULES =
    OrderedDict(# simple assignment
                :(Z = X) => :(Z = X),
                :(Z[i...] = X[i...]) => :(Z .= X),
                # summation
                :(Z = X[i...]) => :(Z = sum(X)),
                :(Z[i] = X[i,j]) => :(Z .= squeeze(sum(X,2),2)),
                :(Z[j] = X[i,j]) => :(Z .= squeeze(sum(X,1),1)),
                :(Z[i,j] = X[i,j,k]) => :(Z .= squeeze(sum(X,3),3)),
                :(Z[i,k] = X[i,j,k]) => :(Z .= squeeze(sum(X,2),2)),
                :(Z[j,k] = X[i,j,k]) => :(Z .= squeeze(sum(X,1),1)),
                # repmat
                # :(Z[i,j] = X[j]) => :(Z = repmat(X', size__(Z)[1])),
                # :(Z[i,j] = X[i]) => :(Z = repmat(X, 1, size__(Z)[2])),
                # eye
                # :(Z[i,j] = 1 * (i == j)) => :(Z = eye(size__(Z))[1]),
                # constant
                # :(Z[i...] = X) => :(Z = ones(size__(Z)) * X),
                # other cases
                #:(Z[i,j] = X[j,k]) => :(Z = repmat(squeeze(sum(X, 2), 2)', size__(Z)[1]))
                )



const TO_BUFFERED_CONST_RULES =
    OrderedDict(:(Z = X) => :(Z = X),
                :(Z[i...] = X) => :(Z = ones(size__(Z)) * X),
                # constant expressions
                :(Z = length(X[::])) => :(Z = length(X)),
                )



function to_buffered(g::EinGraph)
    evaluate!(g)
    g = fuse_broadcasting(g)
    res = :(begin end)
    for nd in g.tape
        if getcategory(nd) != :input
            vex = to_buffered(g, nd)
            # push!(res.args, simplify(subs_size(vex, sizes)))
            push!(res.args, vex)
        end
    end
    res = subs_bcast_with_dot(sanitize(res))
    return res
end

# to_buffered(g::EinGraph, nd::ExNode{:input}) = getexpr(nd)

function to_buffered(g::EinGraph, nd::ExNode{:constant})
    rsizes = @get_or_create(g.ctx, :rsizes, Dict())
    ex = to_expr(nd)
    for (pat, rpat) in TO_BUFFERED_CONST_RULES
        pat = sanitize(pat)
        rex = tryrewrite(ex, pat, rpat; phs=TO_BUFFERED_PHS, allow_ex=false)
        if !isnull(rex)
            return subs_size(get(rex), rsizes)
        end
    end
    error("Can't convert to buffered node: $nd")
end



function to_buffered(g::EinGraph, nd::ExNode{:call})
    ex = expand_const(g, to_expr(nd)) |> simplify
    if !iscall(ex.args[2])
        return to_buffered(g, convert_call(g, nd))
    end
    if is_special_expr(getexpr(nd))
        # not buffered version, will improve when semantics
        # for special functions gets more clear
        return from_einstein(g, nd)
    end
    for (pat, rpat) in TO_BUFFERED_CALL_RULES
        pat = sanitize(pat)
        rex = tryrewrite(ex, pat, rpat; phs=TO_BUFFERED_PHS, allow_ex=false)
        if !isnull(rex)
            return get(rex)
        end
    end
    if is_bcast_indexed(nd)
        return make_elementwise(without_indices(to_expr(nd));
                                lhs_is_scalar=isempty(varidxs(nd)))
    end
    error("Can't convert to buffered node: $nd")
end


function to_buffered(g::EinGraph, nd::ExNode{:opaque})
    if is_bcast_indexed(nd)
        return make_elementwise(without_indices(to_expr(nd));
                                lhs_is_scalar=isempty(varidxs(nd)))
    else
        return to_expr(nd)
    end
end


function make_elementwise(ex; lhs_is_scalar=false)
    new_ex = macroexpand(:(@. $ex))
    if isa(new_ex, Expr) && new_ex.head == :.= && lhs_is_scalar
        new_ex.head = :(=)  # can't use :.= if LHS is scalar
    end
    return new_ex
end


function to_buffered(g::EinGraph, nd::ExNode{:(=)})
    ex = to_expr(nd)
    for (pat, rpat) in TO_BUFFERED_ASSIGN_RULES
        pat = sanitize(pat)
        rex = tryrewrite(ex, pat, rpat; phs=TO_BUFFERED_PHS, allow_ex=false)
        if !isnull(rex)
            return get(rex)
        end
    end
    error("Can't convert to buffered node: $nd")
end


function to_buffered(g::EinGraph, nd::ExNode{:bcast})
    ex = to_expr(nd)
    vars = findex(:(_x[_i...]), ex)
    st = Dict(var => var.args[1] for var in vars)
    vex = subs(ex, st)
    vex.head = isempty(varidxs(nd)) ? :(=) : :.=
    return vex
end


function to_buffered(g::EinGraph, nd::ExNode{:tuple})
    return without_indices(to_expr(nd))
end
