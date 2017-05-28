
# from Einstein to vectorized notation

const FROM_EIN_PHS = [:A, :B, :C, :X, :Y, :V, :W, :Z,
                      :i, :j, :k, :l, :m, :n, :p, :q, :r, :s, :t]

const FROM_EINSTEIN_CALL_RULES =
    OrderedDict(# inner and outer product
                :(Z[i,j] = X[i] * Y[j]) => :(Z = X * Y'),
                :(Z = X[i] * Y[i]) => :(Z = X'Y),
                :(Z[i,j] = X[i] .* Y[j]) => :(Z = X * Y'),
                :(Z = X[i] .* Y[i]) => :(Z = X'Y),
                # matrix-by-vector
                :(Z[j] = X[i] * Y[i,j]) => :(Z = Y' * X),
                :(Z[i] = X[j] * Y[i,j]) => :(Z = Y * X),
                :(Z[i] = X[i,j] * Y[j]) => :(Z = X * Y),
                :(Z = X[i,j] * Y[j]) => :(Z = sum(X * Y)),
                :(Z[j] = X[i,j] * Y[i]) => :(Z = X' * Y),
                :(Z = X[i,j] * Y[i]) => :(Z = sum(X' * Y)),
                :(Z[j] = X[i] .* Y[i,j]) => :(Z = Y' * X),
                :(Z[i] = X[j] .* Y[i,j]) => :(Z = Y * X),
                :(Z[i] = X[i,j] .* Y[j]) => :(Z = X * Y),
                :(Z[j] = X[i,j] .* Y[i]) => :(Z = X' * Y),
                :(Z[i,j] = X[i,j] .* Y[i]) => :(Z = X .* Y),
                :(Z[i,j] = X[i,j] .* Y[j]) => :(Z = X .* Y'),
                # matrix-by-matrix
                :(Z[i,j] = X[i,k] * Y[k,j]) => :(Z = X * Y),
                :(Z[i,j] = Y[k,j] * X[i,k]) => :(Z = X * Y),
                :(Z[i,j] = X[i,k] .* Y[k,j]) => :(Z = X * Y),
                :(Z[i,j] = Y[k,j] .* X[i,k]) => :(Z = X * Y),
                :(Z[i,j] = Y[i,j] .* X[j,i]) => :(Z = X * Y'),
                # matrix-by-matrix: 3-index rule
                :(Z[i,j] = X[i,k] .* Y[j,k]) => :(Z = X * Y'),
                :(Z[i,j] = X[k,i] .* Y[k,j]) => :(Z = X' * Y),
                :(Z[j,i] = X[i,k] .* Y[j,k]) => :(Z = Y * X'),  # same transposed
                :(Z[j,i] = X[k,i] .* Y[k,j]) => :(Z = Y' * X),  # same transposed
                # special .+ and .*
                :(Z[i,j] = X[j] .+ Y[i,j]) => :(Z = X' .+ Y),
                :(Z[i,j] = X .* Y[j]) => :(Z = repmat((X .* Y)', size__(Z)[1])),
                :(Z[j] = X .* Y[i,j]) => :(Z = X .* squeeze(sum(Y,1),1)),                
                # eye
                :(Z[i,j] = 1 * (i == j)) => :(Z = eye(size__(Z))[1]),
                # –> ∑ₖxᵢyⱼₖ == xᵢ∑ₖyⱼₖ   # TODO: seems incorrect, see 2-level rules
                # :(Z[i,j] = X[i] .* Y[j,k]) => :(Z = X .* squeeze(sum(Y,2),2))
                # broadcasting + sum
                :(Z = _f(X[i], Y)) => :(Z = sum(_f.(X, Y))),
                :(Z = _f(X, Y[i])) => :(Z = sum(_f.(X, Y))),
                :(Z = _f(X[i], Y[i])) => :(Z = sum(_f.(X, Y))),
                :(Z = _f(X[i,j], Y[i,j])) => :(Z = sum.(_f(X, Y))),
                )


const FROM_EINSTEIN_ASSIGN_RULES =
    OrderedDict(:(Z[i] = X[i,j]) => :(Z = squeeze(sum(X,1),1)),
                :(Z[i,j] = X[i,j,k]) => :(Z = squeeze(sum(X,3),3)),
                :(Z[i,k] = X[i,j,k]) => :(Z = squeeze(sum(X,2),2)),
                :(Z[j,k] = X[i,j,k]) => :(Z = squeeze(sum(X,1),1)),
                # no-pseudoone summation
                :(Z[i] = X[i,j]) => :(Z = squeeze(sum(X,2),2)),
                :(Z[j] = X[i,j]) => :(Z = squeeze(sum(X,1),1)),
                :(Z = X[i]) => :(Z = sum(X)),
                :(Z = X[i,j]) => :(Z = sum(X)),
                :(Z = X[i,j,k]) => :(Z = sum(X)),
                # repmat
                :(Z[i,j] = X[j]) => :(Z = repmat(X', size__(Z)[1])),
                :(Z[i,j] = X[i]) => :(Z = repmat(X, 1, size__(Z)[2])),
                # eye
                :(Z[i,j] = 1 * (i == j)) => :(Z = eye(size__(Z))[1]),
                # constant
                :(Z[i...] = X) => :(Z = ones(size__(Z)) * X),
                # other cases
                :(Z[i,j] = X[j,k]) => :(Z = repmat(squeeze(sum(X, 2), 2)', size__(Z)[1])))


const FROM_EINSTEIN_ASSIGN_2_RULES =
    OrderedDict(:(W[i,j,k] = X[i] .* Y[j,k]; Z[i,j] = W[i,j,k]) =>
                :(Z = X .* sum(Y,2)'),  # since: ∑ₖxᵢyⱼₖ == xᵢ∑ₖyⱼₖ

                :(W[i,j] = X[i] .* Y[j]; Z[k,j] = W[i,j]) =>
                :(Z = repmat((Y * sum(X))', size__(Z)[1])),

                :(W[i,k,j] = X[i,k] .* Y[k,j]; Z[i,j] = W[i,k,j]) =>
                :(Z = X * Y),

                :(W[i,k,j] = X[i,k] .* Y[j,k]; Z[i,j] = W[i,k,j]) =>
                :(Z = X * Y')
                )


const FROM_EINSTEIN_CONST_RULES =
    OrderedDict(:(Z = X) => :(Z = X),
                :(Z[i...] = X) => :(Z = ones(size__(Z)) * X),)



function to_einsum(ex::Expr)
    if ex.head == :block
        return to_block(map(to_einsum, ex.args))
    else
        @assert ex.head == :(=)
        uex = unguarded(ex)
        return :(@einsum $(uex.args[1]) := $(uex.args[2]))
    end
end


function from_einstein(ex::Expr; ctx=Dict(), inputs...)
    g = EinGraph(ex; ctx=ctx, inputs...)
    return from_einstein(g)
end


function from_einstein(g::EinGraph)
    sizes = @get(g.ctx, :sizes, Dict())
    res = :(begin end)
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            vex = from_einstein(g, nd)
            push!(res.args, simplify(subs_size(vex, sizes)))
        end
    end
    # res = remove_unused(res) # can't remove unused because last expression
                               # may not be output var
    res = sanitize(res)
    return res
end

from_einstein(g::EinGraph, nd::ExNode{:input}) = getexpr(nd)

function from_einstein(g::EinGraph, nd::ExNode{:constant})
    ex = to_expr(nd)
    for (pat, rpat) in FROM_EINSTEIN_CONST_RULES       
        rex = tryrewrite(ex, pat, rpat; phs=FROM_EIN_PHS, allow_ex=false)
        if !isnull(rex)
            return get(rex)
        end
    end
    throw(ErrorException("Can't convert to vectorized notation constant node: $nd"))
end


function from_einstein(g::EinGraph, nd::ExNode{:call})
    ex = to_expr(nd)
    for (pat, rpat) in FROM_EINSTEIN_CALL_RULES
        # consider tryrewrite
        rex = tryrewrite(ex, pat, rpat; phs=FROM_EIN_PHS, allow_ex=false)
        if !isnull(rex)
            return get(rex)
        end
    end
    if length(varidxs(nd)) >= 3
        error("Can't convert to vectorized notation a tensor of " *
              "$(length(varidxs(nd))) dimensions: $(to_expr(nd))")
    end
    # if no pattern matches, try broadcasting
    all_idxs = get_indices(to_expr(nd))
    longest_idx = longest_index(all_idxs)
    is_bcast = (all(idx -> idx == longest_idx || isempty(idx), all_idxs))
    is_bcast_old = in(ex.args[2].args[1], Set([:.*, :.+, :.-, :./, :.^]))
    # TODO: cover things like Z[i] = X[i] .+ Y[i,j]
    if is_bcast_old
        # nearly deprecated syntax, but still actively used in 0.6
        call = Expr(:call, getexpr(nd).args[1], dependencies(nd)...)
        # TODO: this doesn't cover implicit summation, e.g. `z = x[i] .* y`
        # we can cover it using rules above or track forall indices
        return Expr(:(=), varname(nd), call)
    elseif is_bcast
        bcast_call = Expr(:., getexpr(nd).args[1], Expr(:tuple, dependencies(nd)...))
        return Expr(:(=), varname(nd), bcast_call)
    else
        error("Neither pattern found, nor broadcasting is applicable when transforming from " *
              "Einstein notation, expression: $ex")
        # return to_einsum(ex)
    end
end


function from_einstein(g::EinGraph, nd::ExNode{:(=)})
    # first try 2-level rules
    ex = expand_deps(g, nd, 1)
    for (pat, rpat) in FROM_EINSTEIN_ASSIGN_2_RULES
        rex = tryrewrite(ex, pat, rpat; phs=FROM_EIN_PHS, allow_ex=false)
        if !isnull(rex)
            return get(rex)
        end
    end
    # then check 1-level rules
    ex = to_expr(nd)
    for (pat, rpat) in FROM_EINSTEIN_ASSIGN_RULES
        rex = tryrewrite(ex, pat, rpat; phs=FROM_EIN_PHS, allow_ex=false)
        if !isnull(rex)
            return get(rex)
        end
    end
    vidxs = varidxs(nd)
    depidxs = get_indices(getexpr(nd))[1]
    # if LHS contains indices not in RHS, fail since all such cases
    # should be covered by rules above
    if !isempty(setdiff(vidxs, depidxs))
        throw(ErrorException("LHS contains indices not in RHS in: $(to_expr(nd))"))
    end
    # otherwise assume summation and/or permutation
    new_ex = without_indices(getexpr(nd))
    sum_idxs = setdiff(depidxs, varidxs(nd))
    if  !isempty(sum_idxs)
        lhs_idxs = depidxs
        sum_dims = [findfirst(lhs_idxs, idx) for idx in sum_idxs]
        @assert length(sum_idxs) == 1 "Currently from_enstein() support only " *
            "summing over a single dimension. Expression was: $(to_expr(nd))"
        sum_dim = sum_dims[1]
        new_ex = :(squeeze(sum($(new_ex), $(sum_dim)), $(sum_dim)))
    end
    new_rhs_idxs = [idx for idx in depidxs if !in(idx, sum_idxs)]
    perm = findperm(varidxs(nd), new_rhs_idxs)
    if !all(perm .== 1:length(perm))
        if length(perm) == 2
            new_ex = :(transpose($new_ex))
        else
            new_ex = :(permutedims($new_ex, $perm))
        end
    end
    return Expr(:(=), varname(nd), new_ex)
end


function from_einstein(g::EinGraph, nd::ExNode{:bcast})
    ex = to_expr(nd)
    vars = findex(:(_x[_i...]), ex)
    st = Dict(var => var.args[1] for var in vars)
    return subs(ex, st)
end


function from_einstein(g::EinGraph, nd::ExNode{:tuple})
    return without_indices(to_expr(nd))
end
