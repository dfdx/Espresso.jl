
if !isdefined(:__EXPRESSION_HASHES__)
    __EXPRESSION_HASHES__ = Set{UInt64}()
end

macro runonce(expr)
    h = hash(expr)
    return esc(quote
        if !in($h, __EXPRESSION_HASHES__)
            push!(__EXPRESSION_HASHES__, $h)
            $expr
        end
    end)
end


function flatten!(b::Vector, a::Vector)
    for x in a
        if isa(x, Array)
            flatten!(b, x)
        else
            push!(b, x)
        end
    end
    return b
end

flatten(a::Vector) = flatten!(eltype(a)[], a)
flatten{T}(::Type{T}, a::Vector) = convert(Vector{T}, flatten(a))
