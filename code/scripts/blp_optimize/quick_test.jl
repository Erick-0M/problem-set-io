using MAT, DataFrames, Statistics, LinearAlgebra, JLD2
include("blp_new.jl")
using .blp
Threads.nthreads()
const TOLER = 1e-4      # contraction tolerance (precise runs: 1e-12)
const MAX_ITER = 1000   # contraction iterations
const NS = 1            # starting points
const ITERATIONS = 15   # optimizer iterations per start
const OUTDIR = "models_quick"
mkpath(OUTDIR)

beta = [5, 1, 1]; alpha_bar = -1; gamma = [2, 1, 1]; sigma = 1.0
simdir = "../build/input/public/simulation"
d1 = matread(joinpath(simdir, "10markets3products.mat"))
d2 = matread(joinpath(simdir, "100markets3products.mat"))

function process_data(d)
    J, T = size(d["P_opt"])
    p = reshape(d["P_opt"], (T*J, 1)); shares = reshape(d["shares"], (T*J, 1))
    data = blp.BLPData(T, J, d["x1"], p, shares, log.(d["alphas"] .- 1))
    model = blp.BLPDemand(BLPData = data)
    model.xi_real = d["xi_all"]
    model.cost = gamma[1] .+ (gamma[2] * d["w"] + gamma[3] * d["Z"] + d["eta"])
    model.markup .= ((model.p - model.cost) ./ model.p)
    model.profit = (model.p - model.cost) .* model.shares
    return model
end

# Estimates a model with the quick settings and saves it
function estimate!(model, name)
    t = @elapsed if model isa blp.BLPDemand
        blp.estimate_blp!(model; toler = TOLER, max_iter = MAX_ITER, Ns = NS, iterations = ITERATIONS)
    else
        blp.estimate_blp_joint!(model; toler = TOLER, max_iter = MAX_ITER, Ns = NS, iterations = ITERATIONS)
    end
    jldsave(joinpath(OUTDIR, "$name.jdl2"); model = model)
    println("$name: $(round(t, digits = 1))s, params = ", round.(vec(model.params), digits = 4))
    return model
end

timings = Dict{String, Float64}()
set_Z!(m, Z) = (m.Z = Z; m.W = inv(Z' * Z); m)
model = process_data(d2)
model.beta .= vcat(beta, [alpha_bar]); model.sigma = sigma
blp.simulate_BLP!(model, delta = model.X_all * model.beta + model.xi_real, sigma = sigma, all = true)

price_bar = blp.compute_hausman(model)
X_rivals = blp.compute_blp(model)
set_Z!(model, hcat(model.X, price_bar, X_rivals))
timings["model"] = @elapsed model = estimate!(model, "model")
model_ls = process_data(d1)
p_bar_ls = blp.compute_hausman(model_ls); X_rivals_ls = blp.compute_blp(model_ls)
set_Z!(model_ls, hcat(model_ls.X, p_bar_ls, X_rivals_ls))
timings["model_ls"] = @elapsed model_ls = estimate!(model_ls, "model_ls")
model_inc = deepcopy(model)
set_Z!(model_inc, hcat(model_inc.X_all, price_bar, X_rivals))
timings["model_inc"] = @elapsed model_inc = estimate!(model_inc, "model_inc")
model_ss = deepcopy(model)
set_Z!(model_ss, hcat(model_ss.X, price_bar, X_rivals, d2["w"]))
timings["model_ss"] = @elapsed model_ss = estimate!(model_ss, "model_ss")

model_ls_ss = deepcopy(model_ls)
set_Z!(model_ls_ss, hcat(model_ls_ss.X, p_bar_ls, X_rivals_ls, d1["w"]))
timings["model_ls_ss"] = @elapsed model_ls_ss = estimate!(model_ls_ss, "model_ls_ss")
X_supply = hcat(ones(model.T * model.J, 1), d2["Z"], d2["w"])
Z_supply = hcat(model.X, X_rivals, X_supply[:, 2:end])
model_supply = blp.BLPSupply(X = X_supply, Z = Z_supply, W = inv(Z_supply' * Z_supply))

systems = Dict{String, blp.BLP}()
for (name, Omega) in (("bert", Matrix{Float64}(I, model.J, model.J)), ("coll", ones(model.J, model.J)), ("comp", zeros(model.J, model.J)))
    dem = deepcopy(model_ss)
    dem.Omega = Omega
    sys = blp.BLP(BLPDemand = dem, BLPSupply = deepcopy(model_supply))
    timings["system_$name"] = @elapsed estimate!(sys, "model_system_$name")
    systems[name] = sys
end
summary = DataFrame(
    model = ["model", "model_ls", "model_inc", "model_ss", "model_ls_ss"],
    sigma = [m.params[end] for m in (model, model_ls, model_inc, model_ss, model_ls_ss)],
    price_coef = [m.beta[end] for m in (model, model_ls, model_inc, model_ss, model_ls_ss)],
    seconds = [round(timings[n], digits = 1) for n in ("model", "model_ls", "model_inc", "model_ss", "model_ls_ss")])
summary_sys = DataFrame(
    model = ["bert", "coll", "comp"],
    sigma = [systems[n].params[end] for n in ("bert", "coll", "comp")],
    price_coef = [systems[n].BLPDemand.beta[end] for n in ("bert", "coll", "comp")],
    seconds = [round(timings["system_$n"], digits = 1) for n in ("bert", "coll", "comp")])
summary, summary_sys