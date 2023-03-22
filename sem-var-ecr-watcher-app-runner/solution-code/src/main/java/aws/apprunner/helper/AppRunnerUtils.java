package aws.apprunner.helper;

import aws.apprunner.App;
import com.amazonaws.auth.DefaultAWSCredentialsProviderChain;
import com.amazonaws.services.apprunner.AWSAppRunner;
import com.amazonaws.services.apprunner.AWSAppRunnerClientBuilder;
import com.amazonaws.services.apprunner.model.DescribeServiceRequest;
import com.amazonaws.services.apprunner.model.InternalServiceErrorException;
import com.amazonaws.services.apprunner.model.InvalidRequestException;
import com.amazonaws.services.apprunner.model.InvalidStateException;
import com.amazonaws.services.apprunner.model.ResourceNotFoundException;
import com.amazonaws.services.apprunner.model.Service;
import com.amazonaws.services.apprunner.model.SourceConfiguration;
import com.amazonaws.services.apprunner.model.StartDeploymentRequest;
import com.amazonaws.services.apprunner.model.UpdateServiceRequest;
import com.amazonaws.services.lambda.runtime.LambdaLogger;

import java.util.Optional;

/**
 * Utility class for App Runner service related operations
 */
public class AppRunnerUtils {
	private static final AWSAppRunner APP_RUNNER_CLIENT = AWSAppRunnerClientBuilder.standard()
			.withCredentials(DefaultAWSCredentialsProviderChain.getInstance()).build();

	/**
	 * Describe App Runner service based on serviceARN
	 * @param serviceArn App Runner service ARN
	 * @param logger lambda logger
	 * @return App Runner service definition
	 */
	public static Optional<Service> describeService(String serviceArn, LambdaLogger logger) {
		int retryCount = 1;
		do {
			try {
				return Optional.of(
						APP_RUNNER_CLIENT.describeService(new DescribeServiceRequest().withServiceArn(serviceArn)).getService());
			} catch (ResourceNotFoundException e) {
				logger.log("\nResource unavailable " + serviceArn);
				return Optional.empty();
			} catch (InvalidStateException | InternalServiceErrorException e) {
				logger.log(String.format("\nRetrievable exception encountered %s - %s", e.getMessage(), serviceArn));
				retryCount++;
			}
		} while (retryCount <= App.MAX_RETRIES);
		return Optional.empty();
	}

	/**
	 * Update App Runner service based on serviceARN
	 * @param serviceArn App Runner service ARN
	 * @param sourceConfiguration App Runner service source configuration
	 * @param logger lambda logger
	 * @return OperationID for the update operation
	 */
	public static Optional<String> updateService(String serviceArn, SourceConfiguration sourceConfiguration,
			LambdaLogger logger) {
		int retryCount = 1;
		do {
			try {
				return Optional.of(APP_RUNNER_CLIENT.updateService(
								new UpdateServiceRequest().withServiceArn(serviceArn).withSourceConfiguration(sourceConfiguration))
						.getOperationId());
			} catch (ResourceNotFoundException e) {
				logger.log("\nResource unavailable " + serviceArn);
				return Optional.empty();
			} catch (InvalidRequestException e) {
				logger.log(String.format("\nRequest invalid %s for %s", sourceConfiguration.toString(), serviceArn));
				return Optional.empty();
			} catch (InvalidStateException | InternalServiceErrorException e) {
				logger.log(String.format("\nRetrievable exception encountered %s - %s", e.getMessage(), serviceArn));
				retryCount++;
			}
		} while (retryCount <= App.MAX_RETRIES);
		return Optional.empty();
	}

	/**
	 * Start deployment for App Runner service based on serviceARN
	 * @param serviceArn App Runner service ARN
	 * @param logger lambda logger
	 * @return OperationID for the deployment operation
	 */
	public static Optional<String> deployService(String serviceArn, LambdaLogger logger) {
		int retryCount = 1;
		do {
			try {
				return Optional.of(APP_RUNNER_CLIENT.startDeployment(new StartDeploymentRequest().withServiceArn(serviceArn))
						.getOperationId());
			} catch (ResourceNotFoundException e) {
				logger.log("\nResource unavailable " + serviceArn);
				return Optional.empty();
			} catch (InvalidStateException | InternalServiceErrorException e) {
				logger.log(String.format("\nRetrievable exception encountered %s - %s", e.getMessage(), serviceArn));
				retryCount++;
			}
		} while (retryCount <= App.MAX_RETRIES);
		return Optional.empty();
	}
}
