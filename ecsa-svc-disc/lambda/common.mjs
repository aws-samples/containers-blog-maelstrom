
export function getLastElementFromArn(arn) {
    var aa=arn.split("/");
    return aa[aa.length-1];
}
