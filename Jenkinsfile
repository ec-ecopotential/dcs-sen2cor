node('ci-community') {
  
  stage 'Checkout'
  checkout scm
  
  stage 'Setup environment'
  env.PATH = "${tool 'apache-maven-3.0.5'}/bin:${env.PATH}"
  
  stage 'Package and Deploy'
  sh 'mvn deploy'

}
