seed = 1719253483
print("seed " .. seed)
math.randomseed(seed)
require("util")
nn = require("lib/nn")
inspect = require("lib/inspect")
Server = require("Server")

servers = {
   Server:new():randomize_props(),
   Server:new():randomize_props(),
}
server_stat_count = #(servers[1]:get_stats())

reward_type = "weighted" -- "min_latency"/"weighted"
n_sessions = 1
n_steps_per_session = 2000
balancer_net = nn.new_neural_net({
   neuron_counts = {
      server_stat_count * #servers,
      server_stat_count * #servers * 2,
      #servers
   },
   act_fns = {"sigmoid", "sigmoid"}
})

function make_request_obj(time)
   return {
      receive_timestamp = time,
      done_timestamp = nil,
      steps_to_handle = math.random(1, 10),
      ram_load = math.random() * 0.08,
      disk_load = math.random() * 0.13,
      cpu_load = math.random() * 0.06,
   }
end

function niangi_decision_fn(inputs)
   return nn.feedforward(balancer_net, { inputs = inputs })
end

last_round_robin_idx = 1
function round_robin_decision_fn(inputs)
   local next_idx = last_round_robin_idx + 1
   if next_idx > #servers then next_idx = 1 end
   last_round_robin_idx = next_idx

   local outputs = {}
   for i=1, #servers do
      outputs[i] = 0
   end
   outputs[next_idx] = 1
   return outputs
end

function outputs_to_idx(out)
   local highest = 0
   local highest_idx = 1
   for i, v in ipairs(out) do
      if highest < v then
         highest = v
         highest_idx = i
      end
   end
   return highest_idx
end

-- Returns avg_latency sum of all servers
function run_session(decision_fn)
   time = 100
   local total_session_latency = 0
   local training_data = {}

   for s=1, n_steps_per_session do
      time = time + 100
      local step_data = {inputs={}, outputs={}}
      --printf("\tstep %i/%i", s, n_steps_per_session)

      -- Step all servers
      for i, server in pairs(servers) do
         server:step(time)
         local stats = server:get_stats()
   
         --printf("\t\tserver %i avg_latency: %f", i, stats[1])
   
         -- Gather all server stats into inputs
         for k, v in ipairs(stats) do
            table.insert(step_data.inputs, v)
         end
      end

      -- Make decision
      step_data.raw_outputs = decision_fn(step_data.inputs)
      local decision_idx = outputs_to_idx(step_data.raw_outputs)
      --printf("\t\tdecision: %i", decision_idx)

      -- Calculate sum of avg latencies
      local avg_latency_sum = 0
      local min_avg_latency = 1/0
      for i, server in pairs(servers) do
         if min_avg_latency > server.avg_latency then
            min_avg_latency = server.avg_latency
         end
         avg_latency_sum = avg_latency_sum + server.avg_latency
         total_session_latency = total_session_latency + server.avg_latency
      end

      -- Generate desired outputs based on reward strategy (latency outcomes)
      if reward_type == "min_latency" then
         for i, server in pairs(servers) do
            local x
            if avg_latency_sum == 0 then
               x = 1
            elseif server.avg_latency == min_avg_latency then
               x = 1
            else
               x = 0
            end
   
            step_data.outputs[i] = x
         end
      elseif reward_type == "weighted" then
         for i, server in pairs(servers) do
            local x
            if avg_latency_sum == 0 then
               x = 1/#servers
            else
               x = server.avg_latency / avg_latency_sum
            end

            step_data.outputs[i] = x
         end
      end

      -- Send request
      -- TODO: send multiple requests here later
      servers[decision_idx]:send_request(make_request_obj(time))

      table.insert(training_data, step_data)
   end

   return training_data, total_session_latency
end

-- Returns training data
function run()
   local rr_lat = 0
   for sess=1, n_sessions do
      printf("session %i/%i", sess, n_sessions)
      local training_data, lat = run_session(round_robin_decision_fn)
      rr_lat = lat
      --print(inspect(training_data))
      nn.train(balancer_net, training_data, {
         epochs = 250,
         learning_rate = 0.1,
         log_freq = 0.05,
      })
   end

   -- Reset servers
   for _, s in ipairs(servers) do s:init() end

   -- Test our neural net
   local _, nn_lat = run_session(niangi_decision_fn)

   printf("round robin total session latency: %f", rr_lat / (n_sessions * n_steps_per_session))
   printf("niangi total session latency: %f", nn_lat / (n_sessions * n_steps_per_session))
end

run()

-- local net_str = inspect(nn.compress(balancer_net))
-- local file = io.open("2_servers_net.lua", "w")
-- file:write("return ")
-- file:write(net_str)
-- file:close()
