
# codegen.jl - utils to generate code in different formats from ExGraph and EinGraph

include("codegens/vec.jl")
include("codegens/buf.jl")
include("codegens/cuda.jl")
include("codegens/cudavec.jl")
include("codegens/gpu.jl")


function autoselect_codegen(inputs)
    # assuming inputs is Base.Iterators.Pairs or Vector{Any} with pairs
    first_array_idx = findfirst(a -> isa(a, AbstractArray) && eltype(a) != Any, 
                                [v for (k,v) in inputs])
    first_array_idx != nothing || return VectorCodeGen()
    eltyp = eltype(inputs[first_array_idx][2])
    # we don't want to include CuArrays as dependency, so working on strings
    if any(startswith(string(typeof(v)), "CuArray") for (k, v) in inputs)
        return CuCodeGen(eltyp)
    else
        return BufCodeGen(eltyp)
    end
end
