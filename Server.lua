local Server = {
   pending_requests = nil,
   avg_latency = 0,
   requests_handled = 0,

   cpu_load = 0,
   ram_load = 0,
   disk_load = 0,

   max_cpu_load = 1,
   max_ram_load = 1,
   max_disk_load = 1,

   cpu_penalty = 400,
   ram_penalty = 400,
   disk_penalty = 400,
}

function Server:new(o)
   local instance = o or {}
   setmetatable(instance, self)
   self.__index = self

   instance:init()
   return instance
end

function Server:init()
   self.cpu_load = 0
   self.ram_load = 0
   self.disk_load = 0
   self.pending_requests = {}
   self.requests_handled = 0
end

function Server:randomize_props()
   self.max_cpu_load = 0.5 + math.random() * 1.5
   self.max_ram_load = 0.5 + math.random() * 1.5
   self.max_disk_load = 0.5 + math.random() * 1.5

   self.cpu_penalty = 1000 + math.random() * 3000
   self.ram_penalty = 1000 + math.random() * 3000
   self.disk_penalty = 1000 + math.random() * 3000
   return self
end

function Server:step(time_now)
   for i, req in ipairs(self.pending_requests) do
      req.steps_to_handle = req.steps_to_handle - 1

      -- Done with request
      if req.steps_to_handle <= 0 then
         req.done_timestamp = time_now
         self.requests_handled = self.requests_handled + 1
         self.avg_latency =
            (self.avg_latency * (self.requests_handled - 1) +
               req.done_timestamp - req.receive_timestamp) / self.requests_handled
         self.disk_load = self.disk_load - req.disk_load
         self.cpu_load = self.cpu_load - req.cpu_load
         self.ram_load = self.ram_load - req.ram_load
         table.remove(self.pending_requests, i)
      end
   end
end

function Server:get_stats()
   return {
      self.avg_latency,
      self.cpu_load,
      self.ram_load,
      self.disk_load,
      self.max_cpu_load,
      self.max_ram_load,
      self.max_disk_load,
   }
end

function Server:send_request(req)
   self.cpu_load = self.cpu_load + req.cpu_load
   self.disk_load = self.disk_load + req.disk_load
   self.ram_load = self.ram_load + req.ram_load

   if self.cpu_load > self.max_cpu_load then
      self.avg_latency = self.avg_latency + self.cpu_penalty
   end

   if self.disk_load > self.max_disk_load then
      self.avg_latency = self.avg_latency + self.disk_penalty
   end

   if self.ram_load > self.max_ram_load then
      self.avg_latency = self.avg_latency + self.ram_penalty
   end

   table.insert(self.pending_requests, req)
end

return Server
