using MAT, LinearAlgebra, Statistics
include("blp_new.jl"); using .blp
d = matread("../build/input/public/simulation/100markets3products.mat")
J, T = size(d["P_opt"]); gamma=[2,1,1]
p = reshape(d["P_opt"], (T*J,1)); sh = reshape(d["shares"], (T*J,1))
m = blp.BLPDemand(BLPData=blp.BLPData(T,J,d["x1"],p,sh,log.(d["alphas"] .- 1)))
m.beta .= [5,1,1,-1]; m.sigma = 1.0
cost = gamma[1] .+ (gamma[2]*d["w"] + gamma[3]*d["Z"] + d["eta"])
delta = m.X_all*m.beta + d["xi_all"]
blp.simulate_BLP!(m, delta=delta, sigma=1.0, all=true)
println("true cost range ", extrema(cost), "  recovered ", extrema(m.cost_sim))
println("corr = ", cor(vec(cost), vec(m.cost_sim)), "  mean diff = ", mean(m.cost_sim - cost), " max abs diff = ", maximum(abs.(m.cost_sim - cost)))
println("sim vs data shares max abs diff = ", maximum(abs.(m.shares_sim - m.shares)))
