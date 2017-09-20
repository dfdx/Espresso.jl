
struct CuCodeGen
    buf_var_name::Symbol
end

const FT = Float64

const CUDA_NATIVE_RULES = [
    :(log.(x)) => :(CUDAnative.log.(x)),
    :(exp.(x)) => :(CUDAnative.exp.(x)),
    :(sqrt.(x)) => :(CUDAnative.sqrt.(x)),
    :(x .^ n) => :(CUDAnative.pow.(x, $FT(n)))
]


function cuda_buffer_expr(var, buffer_var, sz)
    if isempty(sz)
        return :($var = $FT(0.0))
    else    
        return  :($var = @get_or_create($buffer_var, $(Expr(:quote, var)),
                                        GPUArray(zeros($FT, $sz))))
    end
end



function generate_code(codegen::CuCodeGen, g::EinGraph)
    g = eliminate_common(g)
    ex = to_buffered(g)
    ex = rewrite_all(ex, CUDA_NATIVE_RULES; phs=[:x, :y, :z, :n])
    buffer_var = codegen.buf_var_name
    init_exs = [cuda_buffer_expr(var, buffer_var, sz) for (var, sz) in g.ctx[:rsizes]
                if haskey(g, var) && getcategory(g[var]) != :input]
    res = Expr(:block, init_exs..., ex.args...)
    return res
end
