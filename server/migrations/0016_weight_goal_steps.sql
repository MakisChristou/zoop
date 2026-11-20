ALTER TABLE weight_goals ADD COLUMN daily_steps_goal integer CHECK (daily_steps_goal BETWEEN 1 AND 100000);
