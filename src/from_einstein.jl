
# from Einstein to vectorized notation

const FROM_EIN_PHS = [:A, :B, :C, :X, :Y, :V, :W, :Z,
                      :i, :j, :k, :l, :m, :n, :p, :q, :r, :s, :t]

const FROM_EINSTEIN_CALL_RULES =
    OrderedDict(:(Z[j] = I[i] * X[i,j]) => :(Z = squeeze(sum(X,1),1)),
                :(Z[i] = I[j] * X[i,j]) => :(Z = squeeze(sum(X,2),2)),
                :(Z[i] = X[i,j] * I[j]) => :(Z = squeeze(sum(X,2),2)),
                :(Z[j] = X[i,j] * I[i]) => :(Z = squeeze(sum(X,1),1)),
                :(Z[i,j] = X[i,j,k] * I[k]) => :(Z = squeeze(sum(X,3),3)),
                :(Z[i,k] = X[i,j,k] * I[j]) => :(Z = squeeze(sum(X,2),2)),
                :(Z[j,k] = X[i,j,k] * I[i]) => :(Z = squeeze(sum(X,1),1)),
                :(Z = X[i] * I[i]) => :(Z = sum(X)),
                :(Z = I[i] * X[i]) => :(Z = sum(X)),
                :(Z = X[i,j] * I[i,j]) => :(Z = sum(X)),
                :(Z = I[i,j] * X[i,j]) => :(Z = sum(X)),
                # inner and outer product
                :(Z[i,j] = X[i] * Y[j]) => :(Z = X * Y'),
                :(Z = X[i] * Y[i]) => :(Z = X'Y),
                :(Z[i,j] = X[i] .* Y[j]) => :(Z = X * Y'),
                :(Z = X[i] .* Y[i]) => :(Z = X'Y),
                # matrix-by-vector
                # TODO: check rules below once again
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
                # eye
                :(Z[i,j] = 1 * (i == j)) => :(eye(size__(Z))[1]),
                # special .+ and .*
                :(Z[i,j] = X[j] .+ Y[i,j]) => :(Z = X' .+ Y),
                # –> ∑ₖxᵢyⱼₖ == xᵢ∑ₖyⱼₖ   # TODO: seems incorrect, see 2-level rules
                :(Z[i,j] = X[i] .* Y[j,k]) => :(Z = X .* squeeze(sum(Y,2),2))
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
                :(Z[i,j] = 1 * (i == j)) => :(eye(size__(Z))[1]),
                # constant
                :(Z[i] = X) => :(Z = ones(size__(Z)) * X),
                # other cases
                :(Z[i,j] = X[j,k]) => :(Z = repmat(squeeze(sum(X, 2), 2)', size__(Z)[1])))


const FROM_EINSTEIN_ASSIGN_2_RULES =
    OrderedDict(:(W[i,j,k] = X[i] .* Y[j,k]; Z[i,j] = W[i,j,k]) =>  
                :(Z = X .* sum(Y,2)'),  # since: ∑ₖxᵢyⱼₖ == xᵢ∑ₖyⱼₖ

                :(W[i,j] = X[i] .* Y[j]; Z[k,j] = W[i,j]) =>
                :(repmat((Y * sum(X))', size__(Z)[1]))
                )



function subs_size(ex::Expr, sizes::Dict)
    size_exs = findex(:(size__(_)), ex)
    st = Dict{Any,Any}()
    for size_ex in size_exs
        var, idxs = split_indexed(size_ex.args[2])
        subsex = @get(sizes, var, error("Can't find size for $var in $ex"))
        st[size_ex] = subsex
    end
    return subs(ex, st)
end

subs_size(x, sizes::Dict) = x


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
    g_ = ExGraph(ex; ctx=ctx, inputs...)
    g = optimize(g_)
    propagate_deriv_size!(g)  # TODO: Espresso shouldn't know about derivatives
    # propagate_size!(g)
    sizes = @get(g.ctx, :sizes, Dict())
    res = :(begin end)
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            vex = from_einstein(g, nd)
            push!(res.args, simplify(subs_size(vex, sizes)))
        end
    end
    # res = remove_unused(res, varname(g[end]))
    res = sanitize(res)
    return res
end

from_einstein(g::ExGraph, nd::ExNode{:input}) = expr(nd)
from_einstein(g::ExGraph, nd::ExNode{:constant}) = to_expr(nd)


function from_einstein(g::ExGraph, nd::ExNode{:call})
    ex = to_expr(nd)
    for (pat, rpat) in FROM_EINSTEIN_CALL_RULES
        # consider tryrewrite
        rex = tryrewrite(ex, pat, rpat; phs=FROM_EIN_PHS, allow_ex=false)
        if !isnull(rex)
            return get(rex)
        end
    end
    # if no pattern matches, try broadcasting
    all_idxs = get_indices(to_expr(nd))
    longest_idx = longest_index(all_idxs)
    is_bcast = (all(idx -> idx == longest_idx || isempty(idx), all_idxs))
    is_bcast_old = in(ex.args[2].args[1], Set([:.*, :.+, :.-, :./, :.^]))
    # TODO: cover things like Z[i] = X[i] .+ Y[i,j]
    if is_bcast_old
        # nearly deprecated syntax, but still actively used in 0.6
        call = Expr(:call, expr(nd).args[1], dependencies(nd)...)
        return Expr(:(=), varname(nd), call)
    elseif is_bcast
        bcast_call = Expr(:., expr(nd).args[1], Expr(:tuple, dependencies(nd)...))
        return Expr(:(=), varname(nd), bcast_call)
    else
        error("Neither pattern found, nor broadcasting is applicable when transforming from " *
              "Einstein notation, expression: $ex")
        # return to_einsum(ex)
    end
end


function from_einstein(g::ExGraph, nd::ExNode{:(=)})
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
    depidxs = get_indices(expr(nd))[1]
    # if LHS contains indices not in RHS, fail since all such cases
    # should be covered by rules above
    if !isempty(setdiff(vidxs, depidxs))
        throw(ErrorException("LHS contains indices not in RHS in: $(to_expr(nd))"))
    end
    # otherwise assume summation and/or permutation    
    new_ex = without_indices(expr(nd))    
    sum_idxs = setdiff(depidxs, varidxs(nd))
    if  !isempty(sum_idxs)
        lhs_idxs = depidxs
        sum_dims = [findfirst(lhs_idxs, idx) for idx in sum_idxs]
        @assert length(sum_idxs) == 1 "Currently from_enstein() support only " *
            "summing over a single dimension. Expression was: $(to_iexpr(nd))"
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


function from_einstein(g::ExGraph, nd::ExNode{:bcast})
    ex = to_expr(nd)
    vars = findex(:(_x[_i...]), ex)
    st = Dict(var => var.args[1] for var in vars)
    return subs(ex, st)
end
