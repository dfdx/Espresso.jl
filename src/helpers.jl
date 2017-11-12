
flip(X::Matrix{T}) where {T} = flipdim(flipdim(X, 1), 2)

sum_1(X) = sum(X, 1)
sum_2(X) = sum(X, 2)

squeeze_sum(A::Array{T,N}, dim::Integer) where {T,N} = squeeze(sum(A, dim), dim)
squeeze_sum_1(A) = squeeze_sum(A, 1)
squeeze_sum_2(A) = squeeze_sum(A, 2)


## constructor

function struct_like(m)
    try
        return typeof(m)()
    catch e
        if e isa MethodError
            println("ERROR: Trying to instantiate $(typeof(m)), but it doesn't " *
                    "have a default constructor")            
        end
        throw(e)
    end
end


function __construct(mem::Dict, dzdm_v::Symbol, m; fields...)
    dz!dm = @get_or_create(mem, dzdm_v, struct_like(m))
    for (f, val) in fields
        setfield!(dz!dm, f, val)
    end
    return dz!dm
end


function __construct(m; fields...)
    dz!dm = struct_like(m)
    for (f, val) in fields
        setfield!(dz!dm, f, val)
    end
    return dz!dm
end
