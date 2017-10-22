
# codegen.jl - utils to generate code in different formats from ExGraph and EinGraph

include("codegens/ein.jl")
include("codegens/vec.jl")
include("codegens/buf.jl")
include("codegens/cuda.jl")
include("codegens/gpu.jl")


function autoselect_codegen(inputs)
    # we don't want to include CuArrays as dependency, so working on strings
    if any(startswith(string(typeof(v)), "CuArray") for (k, v) in inputs)
        return CuCodeGen()
    else
        return BufCodeGen()
    end
end
