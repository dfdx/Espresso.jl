
struct GPUCodeGen
    buf_var_name::Symbol
end


function gpu_buffer_expr(var, buffer_var, sz_ex)
    gpu_sz_ex = matchingex(:(zeros(_...)), sz_ex) ? :(GPUArray($sz_ex)) : sz_ex
    return :($var = @get_or_create $buffer_var $(Expr(:quote, var)) $gpu_sz_ex)
end
