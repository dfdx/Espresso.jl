
# to_blas.jl - transform EinGraph to BLAS/in-place operations
#
# Unlike blassify.jl, to_blas.jl works on EinGraph and is more similar
# to from_einstein.jl.
# blassify / to_blas are part of experimental API and may be deprecated.

const TO_BLAS_PHS = [:A, :B, :C, :X, :Y, :V, :W, :Z,
                      :i, :j, :k, :l, :m, :n, :p, :q, :r, :s, :t]

const TO_BLAS_CALL_RULES =
    OrderedDict(# inner and outer product
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
                # # matrix-by-matrix: 3-index rule
                :(Z[i,j] = X[i,k] .* Y[j,k]) => :(A_mul_Bt!(Z, X, Y)),
                :(Z[i,j] = X[k,i] .* Y[k,j]) => :(At_mul_B!(Z, X, Y)),
                :(Z[j,i] = X[i,k] .* Y[j,k]) => :(A_mul_Bt!(Z, Y, X)),  # same transposed
                :(Z[j,i] = X[k,i] .* Y[k,j]) => :(At_mul_B!(Z, Y, X)),  # same transposed
                # # special .+ and .*
                :(Z[i,j] = X[i,j] .+ Y[i]) => :(Z .= X .+ Y),
                :(Z[i,j] = X[i] .+ Y[i,j]) => :(Z .= X .+ Y),
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
                :(Z = _f(X[i...], Y[i...])) => :(Z = sum(_f.(X, Y))),
                # :(Z = _f(X[i,j], Y[i,j])) => :(Z = sum.(_f(X, Y))),
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
                # :(Z = _M._f(X[i,j], Y[i,j])) => :(Z = sum.(_M._f(X, Y))),
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


const TO_BLAS_ASSIGN_RULES =
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



const TO_BLAS_CONST_RULES =
    OrderedDict(:(Z = X) => :(Z = X),
                :(Z[i...] = X) => :(Z = ones(size__(Z)) * X),)



function to_blas(g::EinGraph)
    evaluate!(g)
    g = fuse_broadcasting(g)
    res = :(begin end)
    for nd in g.tape
        if getcategory(nd) != :input
            vex = to_blas(g, nd)
            # push!(res.args, simplify(subs_size(vex, sizes)))
            push!(res.args, vex)
        end
    end
    res = subs_bcast_with_dot(sanitize(res))
    return res
end

# to_blas(g::EinGraph, nd::ExNode{:input}) = getexpr(nd)

function to_blas(g::EinGraph, nd::ExNode{:constant})
    ex = to_expr(nd)
    for (pat, rpat) in TO_BLAS_CONST_RULES
        rex = tryrewrite(ex, pat, rpat; phs=TO_BLAS_PHS, allow_ex=false)
        if !isnull(rex)
            return get(rex)
        end
    end
    error("Can't convert to BLAS node: $nd")
end



function to_blas(g::EinGraph, nd::ExNode{:call})
    ex = expand_const(g, to_expr(nd)) |> simplify
    if !iscall(ex.args[2])
        return to_blas(g, convert_call(g, nd))
    end
    if is_bcast_indexed(nd)
        return make_elementwise(without_indices(to_expr(nd)))
    end
    for (pat, rpat) in TO_BLAS_CALL_RULES
        rex = tryrewrite(ex, pat, rpat; phs=TO_BLAS_PHS, allow_ex=false)
        if !isnull(rex)
            return get(rex)
        end
    end
    error("Can't convert to BLAS node: $nd")
end


function to_blas(g::EinGraph, nd::ExNode{:opaque})
    if is_bcast_indexed(nd)
        return make_elementwise(without_indices(to_expr(nd)))
    else
        return to_expr(nd)
    end
end


make_elementwise(ex) = macroexpand(:(@. $ex))


function to_blas(g::EinGraph, nd::ExNode{:(=)})
    ex = to_expr(nd)
    for (pat, rpat) in TO_BLAS_ASSIGN_RULES
        rex = tryrewrite(ex, pat, rpat; phs=TO_BLAS_PHS, allow_ex=false)
        if !isnull(rex)
            return get(rex)
        end
    end
    error("Can't convert to BLAS node: $nd")
end


function to_blas(g::EinGraph, nd::ExNode{:bcast})
    ex = to_expr(nd)
    vars = findex(:(_x[_i...]), ex)
    st = Dict(var => var.args[1] for var in vars)
    vex = subs(ex, st)
    vex.head = :.=
    return vex
end


function to_blas(g::EinGraph, nd::ExNode{:tuple})
    return without_indices(to_expr(nd))
end






# function main_813()
#     inputs = [:W => rand(2,3), :x => rand(3), :b => rand(2)]
#     g = EinGraph(to_einstein(:(z = log.(exp.(W * x .+ b))); inputs...); inputs...)
#     bex, sizes = to_blas(g)
# end
