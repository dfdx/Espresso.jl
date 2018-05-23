
# type for generating vectorized code
struct VectorCodeGen
    eltyp::Type
end

VectorCodeGen() = VectorCodeGen(Float64)

function generate_code(codegen::VectorCodeGen, g::ExGraph, nd::ExNode)
    # nd = cast_const_type(nd, codegen.eltyp)
    ex = to_expr_kw(nd)
    return ex
end


function generate_code(codegen::VectorCodeGen, g::ExGraph)
    # g = cast_const_type(nd, codegen.eltyp)
    g = eliminate_common(g)
    ex = to_expr_kw(g)
    return ex
end


"""
For buffered codegens, return unbuffered version that can be used in evaluate!()
"""
eval_codegen(codegen::VectorCodeGen) = codegen
