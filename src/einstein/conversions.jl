
## to Einstein notation

"""Transform expression into Einstein notation, infer types from vals"""
to_einstein(ex::Expr, vals...) = to_einstein(to_excall(ex), vals...)

function add_indices(ex, s2i::Dict)
    st = [(k => Expr(:ref, k, v...)) for (k, v) in s2i]
    return subs(ex, st)
end

function to_einstein(exc::ExCall{:*}, ::AbstractMatrix, ::AbstractMatrix)
    ex = to_expr(exc)
    A, B = ex.args[2:3]
    return add_indices(ex, Dict(A => [:i, :k], B => [:k, :j]))
end

function to_einstein(exc::ExCall{:*}, ::AbstractMatrix, ::AbstractVector)
    ex = to_expr(exc)
    A, B = ex.args[2:3]
    return add_indices(ex, Dict(A => [:i, :k], B => [:j]))
end

function to_einstein(exc::ExCall{:*}, ::AbstractVector, BM::AbstractMatrix)
    @assert(size(BM, 1) == 1,
            "Can only multiplicate vector by matrix of size 1 x n, " *
            "got matrix of size $(size(BM))")
    ex = to_expr(exc)
    A, B = ex.args[2:3]
    return add_indices(ex, Dict(A => [:i], B => [:i]))
end

function to_einstein(exc::ExCall{:*}, ::AbstractVector, ::AbstractVector)
    ex = to_expr(exc)
    A, B = ex.args[2:3]
    return add_indices(ex, Dict(A => [:i], B => [:i]))
end

function to_einstein(exc::ExCall{:*}, AA::AbstractArray, BA::AbstractArray)
    error("Multiplication of arrays of size $(size(AA)) and $(size(BA))) " *
          "is undefined")
end

Base.getindex{T}(::UniformScaling{T}, ::Int64) = one(T)
Base.getindex{T}(::UniformScaling{T}, I...) = ones(T, length(I))

function to_einstein{T}(ex::ExCall{:sum}, ::AbstractArray{T,1})
    A = ex.args[2]
    return :($(A)[:i] * I[:i])
end


function to_einstein{T,N}(exc::ExCall, ::AbstractArray{T,N})
    ex = to_expr(exc)
    A = ex.args[2]
    if N > length(IDX_NAMES)
        error("Ran out of index names for this tensor!")
    end
    return add_indices(ex, Dict(A => IDX_NAMES[1:N]))
end

function to_einstein{T,N}(exc::ExCall, ::AbstractArray{T,N}, ::AbstractArray{T,N})
    ex = to_expr(exc)
    A, B = ex.args[2:3]
    if N > length(IDX_NAMES)
        error("Ran out of index names for this tensor!")
    end
    return add_indices(ex, Dict(A => IDX_NAMES[1:N], B => IDX_NAMES[1:N]))
end

function to_einstein{T,N}(exc::ExCall, ::AbstractArray{T,N},
                          ::AbstractArray{T,N}, ::AbstractArray{T, N})
    ex = to_expr(exc)
    A, B, C = ex.args[2:4]
    if N > length(IDX_NAMES)
        error("Ran out of index names for this tensor!")
    end
    return add_indices(ex, Dict(A => IDX_NAMES[1:N],
                                B => IDX_NAMES[1:N],
                                C => IDX_NAMES[1:N]))
end


## from Einstein notation

## function from_einstein(ex::ExCall{})
    
    ## end

# multiplication
# x[i] * y[j] ==> x * y'
# x[i] * I[i] ==> sum(x)

# element-wise functions:
# x[i] + y[i] ==> x .+ y
# exp(x[i]) ==> exp.(x)



# NEXT:
# 1. Implement from_einstein using rule engine
# 2. Restore ordinary derivative workflow
# 3. Implement element-wise operations for tensor derivatives
# 4. Check derivative for logistic regression
