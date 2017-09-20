
# codegen.jl - utils to generate code in different formats from ExGraph and EinGraph

include("codegens/ein.jl")
include("codegens/vec.jl")
include("codegens/buf.jl")
include("codegens/cuda.jl")
include("codegens/gpu.jl")
