
struct CuCodeGen
    eltyp::Type
end

const FT = Float32

const CUDA_NATIVE_RULES = [
    :(log.(x)) => :(CUDAnative.log.(x)),
    :(exp.(x)) => :(CUDAnative.exp.(x)),
    :(sqrt.(x)) => :(CUDAnative.sqrt.(x)),
    :(x .^ n) => :(CUDAnative.pow.(x, __FLOAT_TYPE__(n))),
    :(ones(n)) => :(CuArray(ones(__FLOAT_TYPE__, n))),
    # :(transpose(x)) => :(permutedims(x, (2,1))),  -- seems to cauase segfault in complex cases
]


function cuda_buffer_expr(var, eltyp, buffer_var, sz)
    if isempty(sz)
        return :($var = $eltyp(0.0))
    else    
        return :($var = @get_or_create($buffer_var, $(Expr(:quote, var)),
                                       CuArray(zeros($eltyp, $sz))))
    end
end



function generate_code(codegen::CuCodeGen, g::ExGraph, nd::ExNode)
    # nd = cast_const_type(nd, codegen.eltyp)
    ex = to_buffered(g, nd)
    ex = rewrite_all(ex, CUDA_NATIVE_RULES; phs=[:x, :y, :z, :n])
    ex = subs(ex, Dict(:__FLOAT_TYPE__ => codegen.eltyp))
    return ex
end


function generate_code(codegen::CuCodeGen, g::ExGraph)
    g = eliminate_common(g)
    # g = cast_const_type(g, codegen.eltyp)
    ex = to_buffered(g)
    ex = rewrite_all(ex, CUDA_NATIVE_RULES; phs=[:x, :y, :z, :n])
    ex = subs(ex, Dict(:__FLOAT_TYPE__ => codegen.eltyp))
    init_exs = [cuda_buffer_expr(var, codegen.eltyp, :mem, sz) for (var, sz) in g.ctx[:rsizes]
                if haskey(g, var) && getcategory(g[var]) != :input]
    res = Expr(:block, init_exs..., ex.args...)
    return res
end


eval_codegen(codegen::CuCodeGen) = CuVecCodeGen(codegen.eltyp)
