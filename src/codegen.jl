
# codegen.jl - utils to generate code in different formats from ExGraph and EinGraph

include("codegens/vec.jl")
include("codegens/buf.jl")
include("codegens/cuda.jl")
include("codegens/cudavec.jl")
include("codegens/gpu.jl")


function autoselect_codegen(inputs)
    first_array_idx = findfirst(a -> isa(a, AbstractArray), [v for (k,v) in inputs])
    eltyp = eltype(inputs[first_array_idx][2])
    # we don't want to include CuArrays as dependency, so working on strings
    if any(startswith(string(typeof(v)), "CuArray") for (k, v) in inputs)
        return CuCodeGen(eltyp)
    else
        return BufCodeGen(eltyp)
    end
end


# """
# Cast types or element types of constants to `typ` to avoid performance issues
# """
# function cast_const_type(nd::ExNode, typ::Type)
    
#     if isa(nd, ExNode{:constant}) && isa(getvalue(nd), AbstractFloat)
#         new_val = typ(getvalue(nd))
#         new_nd = copy(nd; val=new_val, ex=new_val)        
#     else
#         new_nd = copy(nd)
#     end
#     return new_nd
# end


# function cast_const_type(g::AbstractExGraph, typ::Type)
#     new_g = reset_tape(g)
#     for nd in g
#         push!(new_g, cast_const_type(nd, typ))
#     end
#     return new_g
# end
