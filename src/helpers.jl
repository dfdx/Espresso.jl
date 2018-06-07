
flip(X::Matrix{T}) where {T} = flipdim(flipdim(X, 1), 2)

sum_1(X) = sum(X, dims=1)
sum_2(X) = sum(X, dims=2)

squeeze_sum(A::Array{T,N}, dim::Integer) where {T,N} = squeeze(sum(A, dims=dim), dims=dim)
squeeze_sum_1(A) = squeeze_sum(A, 1)
squeeze_sum_2(A) = squeeze_sum(A, 2)


## constructor

function struct_like(m)
    try
        return typeof(m)()
    catch e
        if e isa MethodError
            println("ERROR: Trying to instantiate mutable type $(typeof(m)), " *
                    "but it doesn't have a default constructor")
        end
        throw(e)
    end
end


function __construct(mem::Dict, dzdm_v::Symbol, m::T; fields...) where T
    if isimmutable(m)
        return __construct_immutable(T; fields...)
    else
        dz!dm = @get_or_create(mem, dzdm_v, struct_like(m))
        for (f, val) in fields
            setfield!(dz!dm, f, val)
        end
        return dz!dm
    end
end


function __construct(m::T; fields...) where T
    if isimmutable(m)
        return __construct_immutable(T; fields...)
    else
        dz!dm = struct_like(m)
        for (f, val) in fields
            setfield!(dz!dm, f, val)
        end
        return dz!dm
    end
end


function __construct_immutable(::Type{T}; fields...) where T
    f2i = Dict((f, i) for (i, f) in enumerate(fieldnames(T)))
    vals = Array{Any}(length(f2i))
    for (f, val) in fields
        vals[f2i[f]] = val
    end
    return T(vals...)
end
