package aws.apprunner.helper;

import com.amazonaws.auth.DefaultAWSCredentialsProviderChain;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.amazonaws.services.sqs.AmazonSQS;
import com.amazonaws.services.sqs.AmazonSQSClientBuilder;
import com.amazonaws.services.sqs.model.SendMessageRequest;

/**
 * Utility class for SQS related operations
 */
public class SqsUtils {
	private static final AmazonSQS SQS_CLIENT = AmazonSQSClientBuilder.standard()
			.withCredentials(DefaultAWSCredentialsProviderChain.getInstance()).build();

	private static final String QUEUE_URL;

	static {
		QUEUE_URL = SQS_CLIENT.getQueueUrl(System.getenv("QUEUE_NAME")).getQueueUrl();
	}

	/**
	 * Send message to SQS queue
	 * @param body message body
	 * @param delayInMin delay in minutes
	 * @param logger lambda logger
	 */
	public static void sendMessage(String body, int delayInMin, LambdaLogger logger) {
		try {
			SendMessageRequest send_msg_request = new SendMessageRequest().withQueueUrl(QUEUE_URL).withMessageBody(body)
					.withDelaySeconds(delayInMin * 60);
			SQS_CLIENT.sendMessage(send_msg_request);
		} catch (Exception e) {
			logger.log(String.format("\nError while sending message %s - %s", body, e.getMessage()));
		}
	}
}
