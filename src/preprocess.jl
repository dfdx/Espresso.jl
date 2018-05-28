## preprocess.jl - preprocess an expression for better parsing

const PREPROCESS_RULES = [
    :(mean(abs2, _)) => :(mean(abs2.(_))),
]

function preprocess(ex)
    return rewrite_all(ex, PREPROCESS_RULES)
end
