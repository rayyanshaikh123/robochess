from locust import HttpUser, between, task


class RoboChessUser(HttpUser):
    wait_time = between(1, 3)

    @task(3)
    def health(self):
        self.client.get("/health")

    @task(1)
    def puzzle_list(self):
        self.client.get("/puzzles/list")
