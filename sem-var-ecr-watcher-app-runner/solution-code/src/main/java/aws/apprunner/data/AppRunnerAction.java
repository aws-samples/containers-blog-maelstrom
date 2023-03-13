package aws.apprunner.data;

public enum AppRunnerAction {
	DEPLOY("DEPLOY"), UPDATE("UPDATE"), NONE("NONE");
	final String action;

	AppRunnerAction(String action) {
		this.action = action;
	}

	public String getAction() {
		return action;
	}

	@Override
	public String toString() {
		return this.getAction();
	}
}
