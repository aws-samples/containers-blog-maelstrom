package aws.apprunner.helper;

import aws.apprunner.App;
import com.amazonaws.auth.DefaultAWSCredentialsProviderChain;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.amazonaws.services.logs.AWSLogs;
import com.amazonaws.services.logs.AWSLogsClientBuilder;
import com.amazonaws.services.logs.model.InputLogEvent;
import com.amazonaws.services.logs.model.PutLogEventsRequest;
import com.amazonaws.services.logs.model.ServiceUnavailableException;

import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

/**
 * Utility class for CloudWatch Logs related operations
 */
public class CloudWatchUtils {

	private static final AWSLogs LOG_CLIENT = AWSLogsClientBuilder.standard()
			.withCredentials(DefaultAWSCredentialsProviderChain.getInstance()).build();
	private static final String EVENTS = "events";

	/**
	 * Send logs to CloudWatch Logs to the specified log group and stream in order to notify
	 * the customer.
	 * @param serviceArn App Runner service ARN
	 * @param messages List of messages to be sent to CloudWatch Logs
	 * @param logger lambda logger
	 */
	public static void sendLog(String serviceArn, List<String> messages, LambdaLogger logger) {
		int retryCount = 1;
		final Optional<String> optionalLogGroup = getLogGroup(serviceArn);
		if (optionalLogGroup.isPresent()){
			final String logGroup = optionalLogGroup.get();
			do {
				try {
					LOG_CLIENT.putLogEvents(new PutLogEventsRequest(logGroup, EVENTS,
							messages.stream().map(m -> new InputLogEvent().withMessage(m).withTimestamp(System.currentTimeMillis()))
									.collect(Collectors.toList())));
					break;
				} catch (ServiceUnavailableException e) {
					logger.log(String.format("\nRetrievable exception encountered %s - %s", e.getMessage(), logGroup));
					retryCount++;
				}
			} while (retryCount <= App.MAX_RETRIES);
		}

	}

	/**
	 * Get CloudWatch Logs log group name based on serviceARN
	 * @param serviceArn App Runner service ARN
	 * @return CloudWatch Logs log group name
	 */
	public static Optional<String> getLogGroup(String serviceArn) {
		final String[] serviceArnSplit = serviceArn.split("/");
		if (serviceArnSplit.length == 3) {
			final String serviceName = serviceArnSplit[1];
			final String serviceId = serviceArnSplit[2];
			return Optional.of(String.format("/aws/apprunner/%s/%s/service", serviceName, serviceId));
		}
		return Optional.empty();
	}
}
