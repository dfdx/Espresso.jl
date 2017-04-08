

# einstein.jl - utils for working with expressions in Einstein notation

# const IDX_NAMES = [:i, :j, :k, :l, :m, :n, :p, :q, :r, :s]


# function isindexed(ex)
#     return exprlike(ex) && (ex.head == :ref || any(isindexed, ex.args))
# end

# isvectorized(ex) = exprlike(ex) && !isindexed(ex)

# is_einstein(ex) = !isempty(indexed_vars(ex))


# function indexed(ex::Expr, idxs::Vector)
#     @assert (ex.head == :ref) "Argument is not a symbol and not indexed already"
#     return ex
# end

# function indexed(var::Symbol, idxs::Vector)
#     return Expr(:ref, var, idxs...)
# end


# function maybe_indexed(var::Symbol, idxs::Vector)
#     return length(idxs) > 0 ? Expr(:ref, var, idxs...) : var
# end


# parse_indexed(var) = (var, Symbol[])

# function parse_indexed(ex::Expr)
#     @assert ex.head == :ref
#     return convert(Symbol, ex.args[1]), convert(Vector{Symbol}, ex.args[2:end])
# end

# call_indices(x::Symbol) = [Symbol[]]

# function call_indices(ex::Expr)
#     if ex.head == :call     # e.g. :(x[i] + 1)
#         return [parse_indexed(arg)[2] for arg in ex.args[2:end]]
#     elseif ex.head == :(=)  # e.g. :(y[i] = x[i] + 1)
#         lhs_idxs = parse_indexed(ex.args[1])[2]
#         rhs_idxs = call_indices(ex.args[2])
#         return vcat([lhs_idxs], rhs_idxs)
#     else
#         error("Don't know how to extract indices from expression $ex")
#     end
# end


function add_indices(ex, s2i::Dict)
    st = Dict([(k, maybe_indexed(k, v)) for (k, v) in s2i])
    return subs(ex, st)
end








# LHS inference (not used for now)

function infer_lhs(ex::Expr; outvar=:_R)
    idxs = forall_indices(ex)
    return Expr(:ref, outvar, idxs...)
end


function with_lhs(ex::Expr; outvar=:_R)
    lhs = infer_lhs(ex; outvar=outvar)
    return Expr(:(=), lhs, ex)
end


# einsum



function to_einsum(ex::Expr)
    if ex.head == :block
        return to_block(map(to_einsum, ex.args))
    else
        @assert ex.head == :(=)
        uex = unguarded(ex)
        return :(@einsum $(uex.args[1]) := $(uex.args[2]))
    end
end


# index permutations

findperm(idxs1, idxs2) = [findfirst(idxs2, idx) for idx in idxs1]
