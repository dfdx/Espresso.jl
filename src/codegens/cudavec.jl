

struct CuVecCodeGen
    eltyp::Type
end


function generate_code(codegen::CuVecCodeGen, g::ExGraph, nd::ExNode)
    # nd = cast_const_type(nd, codegen.eltyp)
    ex = to_expr_kw(nd)
    ex = rewrite_all(ex, CUDA_NATIVE_RULES; phs=[:x, :y, :z, :n])
    ex = subs(ex, Dict(:__FLOAT_TYPE__ => codegen.eltyp))
    return ex
end


function generate_code(codegen::CuVecCodeGen, g::ExGraph)
    g = eliminate_common(g)
    # g = cast_const_type(g, codegen.eltyp)
    ex = to_expr_kw(g)
    ex = rewrite_all(ex, CUDA_NATIVE_RULES; phs=[:x, :y, :z, :n])
    ex = subs(ex, Dict(:__FLOAT_TYPE__ => codegen.eltyp))
    return ex
end


eval_codegen(codegen::CuVecCodeGen) = codegen
