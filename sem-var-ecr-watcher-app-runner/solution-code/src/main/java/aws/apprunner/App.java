package aws.apprunner;

import aws.apprunner.data.AppRunnerAction;
import aws.apprunner.data.EcrEventRepoDetail;
import aws.apprunner.data.ServiceMatcher;
import aws.apprunner.helper.AppRunnerUtils;
import aws.apprunner.helper.CloudWatchUtils;
import aws.apprunner.helper.S3Utils;
import aws.apprunner.helper.SqsUtils;
import com.amazonaws.services.apprunner.model.ImageRepository;
import com.amazonaws.services.apprunner.model.Service;
import com.amazonaws.services.apprunner.model.SourceConfiguration;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.amazonaws.util.StringUtils;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.vdurmont.semver4j.Semver;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Lambda function to handle SQS events from ECR and handle updates to App Runner services
 */
public class App implements RequestHandler<SQSEvent, List<String>> {
	public static final int MAX_RETRIES = 3;
	private static final String RETRY_COUNT = "retryCount";
	private static final Map<String, ServiceMatcher> SERVICE_MATCHER_MAP = new HashMap<>();
	private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
	private static final String LATEST = "LATEST";
	private static final int DELAY_IN_MIN = 10;
	public static final String IN_PROGRESS = "OPERATION_IN_PROGRESS";

	static {
		// Initialize the semantic version matcher map
		initializeVersionMatcher();
	}

	/**
	 * Lambda function to track for ECR events and update/deploy new version of image to the underlying App Runner service
	 * @param input ECR event received as a SQS event
	 * @param context Lambda context
	 * @return list of operationIDs (based on update/deploy actions)
	 */
	public List<String> handleRequest(final SQSEvent input, final Context context) {
		final LambdaLogger logger = context.getLogger();
		final List<String> deployments = new ArrayList<>();
		for (SQSEvent.SQSMessage record : input.getRecords()) {
			final String body = record.getBody();
			logger.log("\nInput: " + body);
			AppRunnerAction appRunnerAction = AppRunnerAction.NONE;
			Service service = null;
			try {
				// Read the ECR event and extract all the details
				final JsonNode ecrEventNode = OBJECT_MAPPER.readTree(body);
				final EcrEventRepoDetail ecrEventRepoDetail = getEcrEventRepoDetails(ecrEventNode);
				logger.log(String.format("\nExtracted details %s:%s:%s:%s", ecrEventRepoDetail.getAccountId(),
						ecrEventRepoDetail.getRegion(), ecrEventRepoDetail.getRepositoryName(), ecrEventRepoDetail.getImageTag()));

				// Check whether the repository in the ECR event matches with any of repos that we need to watch
				final ServiceMatcher matcher = SERVICE_MATCHER_MAP.get(ecrEventRepoDetail.getRepositoryName());
				if (matcher != null) {
					final Semver semVerEventVersion = new Semver(ecrEventRepoDetail.getImageTag(), Semver.SemverType.NPM);

					// Check whether ECR event imageTag matches the tracked version.
					// example match: ECR Event (1.2.4) and tracked version (>1.2.2)
					if (semVerEventVersion.satisfies(matcher.getSemVersion())) {
						final Optional<Service> serviceOptional = AppRunnerUtils.describeService(matcher.getServiceArn(), logger);

						// Skip the service if CI/CD is enabled, so we don't conflict with the service updates
						if (!serviceOptional.isPresent() || serviceOptional.get().getSourceConfiguration().getAutoDeploymentsEnabled())
							continue;

						// Check whether the current deployed ECR image version of service greater than or less than the
						// new image pushed to ECR, if so we need to update the service to point to the latest image
						service = serviceOptional.get();
						final ImageRepository imageRepository = serviceOptional.get().getSourceConfiguration().getImageRepository();
						if (imageRepository != null) {
							final String targetImageIdentifier = imageRepository.getImageIdentifier();
							final String[] imageSplits = targetImageIdentifier.split(":");
							if (imageSplits.length >= 2) {
								final String serviceVersion = imageSplits[1];
								logger.log(String.format("\nComparing eventTag %s - actualServiceVersion %s",
										ecrEventRepoDetail.getImageTag(), serviceVersion));
								// If the service is pointing to LATEST, we don't perform any action
								if (!LATEST.equalsIgnoreCase(serviceVersion)) {
									// If same imageTag gets updated we need to deploy the service rather than updating it
									if(semVerEventVersion.isEqualTo(serviceVersion)) appRunnerAction = AppRunnerAction.DEPLOY;
									else appRunnerAction = AppRunnerAction.UPDATE;
								}
							}
						}
					} else
						logger.log(String.format("\nSem Version mismatch eventTag %s - watcherVersion %s",
								ecrEventRepoDetail.getImageTag(), matcher.getSemVersion()));

					if (service != null)
						// If there is an ongoing deployment then wait and retry after 10 mins (if we have not reached max retries)
						if (service.getStatus().equalsIgnoreCase(IN_PROGRESS) && appRunnerAction == AppRunnerAction.UPDATE)
							checkAndRetryDeployAction(ecrEventNode, logger);
						else {
							final String serviceArn = service.getServiceArn();
							switch(appRunnerAction) {
								case DEPLOY:
									// Send a cloudwatch event to notify the App Runner deploy action
									final String deployMsg = String.format("[CI/CD] Deploying latest version %s", ecrEventRepoDetail.getImageTag());
									CloudWatchUtils.sendLog(matcher.getServiceArn(), Collections.singletonList(deployMsg), logger);

									// Deploy the service
									final Optional<String> deployOperationId = AppRunnerUtils.deployService(matcher.getServiceArn(), logger);
									deployOperationId.ifPresent(s -> deployments.add(String.format("%s$%s", serviceArn, s)));
									break;
								case UPDATE:
									// Send a cloudwatch event to notify the App Runner update action
									final String updateMsg = String.format(
											"[CI/CD] Semantic version %s matched with the recent ECR push %s, so updating the service to the deploy from the latest version",
											matcher.getSemVersion(), ecrEventRepoDetail.getImageTag());
									CloudWatchUtils.sendLog(matcher.getServiceArn(), Collections.singletonList(updateMsg), logger);

									// Update the service to point to the latest ECR image pushed to repository
									final String newImageIdentifier = String.format("%s.dkr.ecr.%s.amazonaws.com/%s:%s",
											ecrEventRepoDetail.getAccountId(), ecrEventRepoDetail.getRegion(),
											ecrEventRepoDetail.getRepositoryName(), ecrEventRepoDetail.getImageTag());
									final SourceConfiguration sourceConfiguration = service.getSourceConfiguration();
									sourceConfiguration.getImageRepository().setImageIdentifier(newImageIdentifier);
									logger.log(String.format("\nStarting deployment for %s with %s", serviceArn, newImageIdentifier));
									final Optional<String> updateOperationId = AppRunnerUtils.updateService(serviceArn, sourceConfiguration, logger);
									updateOperationId.ifPresent(s -> deployments.add(String.format("%s$%s", serviceArn, s)));
									break;
							}
					}
				} else
					logger.log(String.format("\nNo matcher found so skipping event %s", body));
			} catch (Exception e) {
				logger.log(String.format("\nError while processing a ECR event %s - %s", record.getBody(), e.getMessage()));
				e.printStackTrace();
			}
		}

		return deployments;
	}

	/**
	 * Check whether the deployment is in progress, if so: 1. If we have already retried 3 times then we need to fail the
	 * deployment 2. If we have not retried 3 times then we need to retry after 10 mins
	 *
	 * @param event  ECR event
	 * @param logger Lambda logger
	 */
	private void checkAndRetryDeployAction(JsonNode event, LambdaLogger logger) {
		int retryCount = 1;
		if (event.has(RETRY_COUNT)) {
			retryCount = event.get(RETRY_COUNT).asInt();
			if (retryCount <= MAX_RETRIES)
				retryCount++;
		}

		// Publish a message to SQS with delay of 10 mins
		if (retryCount <= MAX_RETRIES) {
			((ObjectNode) event).put(RETRY_COUNT, retryCount);
			SqsUtils.sendMessage(event.toPrettyString(), DELAY_IN_MIN, logger);
		} else
			logger.log("Max retries exceeded");
	}

	/**
	 * Reads environment variable and creates a map of service arn and target matcher Sample entry: <ecr-repo-name> =
	 * >1.2.2#arn:aws:apprunner:<region>:<account>:service/<name>/<serviceId> Matcher follows NPM versioning rules
	 */
	private static void initializeVersionMatcher() {
		String config = S3Utils.readFile(System.getenv("CONFIG_BUCKET"), System.getenv("CONFIG_FILE"));
		if(!StringUtils.isNullOrEmpty(config)){
			try {
				List<ServiceMatcher> serviceMatcherList = OBJECT_MAPPER.readValue(config, new TypeReference<List<ServiceMatcher>>() {});
				serviceMatcherList.forEach(serviceMatcher -> SERVICE_MATCHER_MAP.put(serviceMatcher.getRepository(), serviceMatcher));
			} catch (Exception e) {
				throw new RuntimeException("Invalid config file");
			}
		}
	}

	/**
	 * Parses the ECR event and returns the repository details
	 *
	 * @param node ECR event
	 * @return ECR repository details
	 */
	private static EcrEventRepoDetail getEcrEventRepoDetails(JsonNode node) {
		final JsonNode details = node.get("detail");
		final String accountId = node.get("account").asText();
		final String region = node.get("region").asText();
		final String repositoryName = details.get("repository-name").asText();
		final String imageTag = details.get("image-tag").asText();
		return new EcrEventRepoDetail(accountId, region, repositoryName, imageTag);
	}
}
