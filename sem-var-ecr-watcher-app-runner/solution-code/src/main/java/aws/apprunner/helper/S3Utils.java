package aws.apprunner.helper;

import com.amazonaws.auth.DefaultAWSCredentialsProviderChain;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;

/**
 * Utility class for S3 related operations
 */
public class S3Utils {

	private static final AmazonS3 S3_CLIENT = AmazonS3ClientBuilder.standard()
			.withCredentials(DefaultAWSCredentialsProviderChain.getInstance()).build();

	/**
	 * Read file from S3 bucket and return the content
	 * @param s3Bucket S3 bucket name
	 * @param key S3 object key
	 * @return file content
	 */
	public static String readFile(String s3Bucket, String key) {
		return S3_CLIENT.getObjectAsString(s3Bucket, key);
	}
}
