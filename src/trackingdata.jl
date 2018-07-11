
struct TReal <: Real
    graph::ExGraph
    var::Symbol
    val::Real
end

TReal(var::Symbol, val::Real) = TReal(get_default_graph(), var, val)
Base.show(io::IO, x::TReal) = print(io, "Tracked $(x.var) = $(x.val)")


struct TArray{T,N} <: AbstractArray{T,N}
    graph::ExGraph
    var::Symbol
    val::AbstractArray{T,N}
end

TArray(var::Symbol, val::AbstractArray) = TArray(get_default_graph(), var, val)
Base.show(io::IO, x::TArray{T,N}) where {T,N} = print(io, "Tracked $(x.var) =\n  $(x.val)")
Base.show(io::IO, ::MIME{Symbol("text/plain")}, x::TArray{T,N}) where {T,N} =
    print(io, "Tracked $(x.var)\n  $(x.val)")


struct TStruct{S}
    graph::ExGraph
    var::Symbol
    val::S
end

TStruct(var::Symbol, val) = TStruct(get_default_graph(), var, val)

Base.show(io::IO, x::TStruct) = print(io, "Tracked\n  $(getfield(x, :val))")
Base.show(io::IO, ::MIME{Symbol("text/plain")}, x::TStruct) where {T,N} =
    print(io, "Tracked\n  $(getfield(x, :val))")


# accessors

value(x::TArray) = x.val
value(x::TReal) = x.val
value(x) = x

istracked(x::TReal) = true
istracked(x::TArray) = true
istracked(x::TStruct) = true
istracked(::Type{T}) where T = (T <: TReal || T <: TArray || T <: TStruct)
istracked(x) = false


# conversion to tracked data

tracked(g::ExGraph, var::Symbol, val::Real) = TReal(g, var, val)
tracked(g::ExGraph, var::Symbol, val::AbstractArray) = TArray(g, var, val)
tracked(g::ExGraph, var::Symbol, val) = isstruct(val) ? TStruct(g, var, val) : error("Not a struct")


# tracked(g::ExGraph, x::TReal) = x
# tracked(g::ExGraph, x::TArray) = x

# function tracked(g::ExGraph, x::T) where {T <: Real}
#     var = genname()
#     push!(g, ExNode{:constant}(var, x; val=x))
#     return TReal(g, var, x)
# end

# function tracked(g::ExGraph, x::T) where {T <: AbstractArray}
#     var = genname()
#     push!(g, ExNode{:constant}(var, x; val=x))
#     return TArray(g, var, x)
# end


## promotion

Base.promote_rule(::Type{TReal}, ::Type{<:Real}) = TReal
function Base.convert(::Type{TReal}, x::R) where {R <: Real}
    var = genname()
    g = get_default_graph()
    push!(g, ExNode{:constant}(var, x; val=x))
    return TReal(g, var, x)
end
Base.convert(::Type{TReal}, x::TReal) = x
Base.convert(::Type{R}, x::TReal) where {R <: Real} = x.val


Base.promote_rule(::Type{TArray}, ::Type{<:AbstractArray}) = TArray
function Base.convert(::Type{TArray}, x::A) where {A <: AbstractArray}
    var = genname()
    g = get_default_graph()
    push!(g, ExNode{:constant}(var, x; val=x))
    return TArray(g, var, x)
end
Base.convert(::Type{TArray}, x::TArray) = x
# Base.convert(::Type{<:AbstractArray}, x::TArray) = x.val


# TODO: should write this to graph? presumably no
# Base.size(x::TArray) = size(x.val)
# TODO: and these? presumably yes, but be carefull about printing
# Base.getindex(x::TArray, I...) = getindex(x.val, I...)
# Base.setindex!(x::TArray, val, I...) = setindex!(x.val, val, I...)
