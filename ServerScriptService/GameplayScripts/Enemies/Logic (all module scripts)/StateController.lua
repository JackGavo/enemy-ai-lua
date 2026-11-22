local StateController = {}
StateController.__index = StateController


function StateController.new(Owner)

	local self = setmetatable({}, StateController)

	self.Owner = Owner

	self.States = {}
	self.CurrentState = nil

	return self
end


function StateController:AddState(Name, Configuration)

	Configuration.Name = Name
	self.States[Name] = Configuration

end


function StateController:SetState(Name)

	local NewState = self.States[Name]

	if not NewState then
		warn("State does not exist:", Name)
		return
	end

	if self.CurrentState then
		if self.CurrentState.Exit then
			self.CurrentState.Exit(self.Owner)
		end
	end

	self.CurrentState = NewState

	if self.CurrentState.Enter then
		self.CurrentState.Enter(self.Owner)
	end

end


function StateController:GetState()

	if not self.CurrentState then
		return nil
	end

	return self.CurrentState.Name

end


function StateController:Evaluate()

	local BestState = nil
	local BestPriority = -math.huge

	for Name, State in self.States do

		if State.CanRun and State.CanRun(self.Owner) then

			if State.Priority > BestPriority then
				BestPriority = State.Priority
				BestState = State
			end

		end

	end

	if BestState and BestState ~= self.CurrentState then
		self:SetState(BestState.Name)
	end

end


function StateController:Update(DeltaTime)

	self:Evaluate()

	if self.CurrentState then

		if self.CurrentState.Update then
			self.CurrentState.Update(self.Owner, DeltaTime)
		end

	end

end


function StateController:Destroy()

	if self.CurrentState and self.CurrentState.Exit then
		self.CurrentState.Exit(self.Owner)
	end

	self.States = {}
	self.CurrentState = nil
	self.Owner = nil

end


return StateController