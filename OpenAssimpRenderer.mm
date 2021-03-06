//
//  OpenCubeRenderer.m
//  OSXGLEssentials
//
//  Created by Matthew Doig on 3/19/14.
//
//

#import "OpenAssimpRenderer.h"

extern "C"
{
    #import "imageUtil.h"
    #import "sourceUtil.h"
}
#import "UtilSrc/objloader.hpp"
#import "glm/glm.hpp"
#import "glm/gtc/matrix_transform.hpp"
#import <iostream>
#import <fstream>
#import <string>
#import <vector>

#define GetGLError()									\
{														\
	GLenum err = glGetError();							\
	while (err != GL_NO_ERROR) {						\
		NSLog(@"GLError %s set in File:%s Line:%d\n",	\
				GetGLErrorString(err),					\
				__FILE__,								\
				__LINE__);								\
		err = glGetError();								\
	}													\
}

// Toggle this to disable vertex buffer objects
// (i.e. use client-side vertex array objects)
// This must be 1 if using the GL3 Core Profile on the Mac
#define USE_VERTEX_BUFFER_OBJECTS 1

// Indicies to which we will set vertex array attibutes
// See buildVAO and buildProgram
enum {
	POS_ATTRIB_IDX,
	TEXCOORD_ATTRIB_IDX
};

#ifndef NULL
#define NULL 0
#endif

#define BUFFER_OFFSET(i) ((char *)NULL + (i))

@interface OpenAssimpRenderer ()

    @property (nonatomic, assign) GLuint defaultFBOName;

    @property (nonatomic, assign) GLuint characterPrgName;
    @property (nonatomic, assign) GLint characterMvpUniformIdx;
    @property (nonatomic, assign) GLuint characterVAOName;
    @property (nonatomic, assign) GLuint characterTexName;
    @property (nonatomic, assign) GLint characterTexUniformIdx;
    @property (nonatomic, assign) GLfloat characterAngle;

    @property (nonatomic, assign) GLuint viewWidth;
    @property (nonatomic, assign) GLuint viewHeight;

    @property (nonatomic, assign) GLboolean useVBOs;

@end

@implementation OpenAssimpRenderer

std::vector<glm::vec3> assPositions;
std::vector<glm::vec2> assTexcoords;
std::vector<glm::vec3> assNormals;
std::vector<unsigned short> assElements;

- (void) resizeWithWidth:(GLuint)width AndHeight:(GLuint)height
{
	glViewport(0, 0, width, height);
    
	self.viewWidth = width;
	self.viewHeight = height;
}

- (void) render
{
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	
	// Use the program for rendering our character
	glUseProgram(self.characterPrgName);
    
    // Projection matrix : 45° Field of View, 4:3 ratio, display range : 0.1 unit <-> 100 units
    glm::mat4 Projection = glm::perspective(45.0f, 4.0f / 3.0f, 0.1f, 100.0f);
    // Camera matrix
    glm::mat4 View       = glm::lookAt(
                                       glm::vec3(4,3,3), // Camera is at (4,3,3), in World Space
                                       glm::vec3(0,0,0), // and looks at the origin
                                       glm::vec3(0,1,0)  // Head is up (set to 0,-1,0 to look upside-down)
                                       );
    // Model matrix : an identity matrix (model will be at the origin)
    glm::mat4 Model      = glm::mat4(1.0f);  // Changes for each model !
    
    Model = glm::rotate(Model, self.characterAngle, glm::vec3(0.0, 1.0, 0.0));
    
    // Our ModelViewProjection : multiplication of our 3 matrices
    glm::mat4 MVP        = Projection * View * Model; // Remember, matrix multiplication is the other way around
    
    // Send our transformation to the currently bound shader,
    // in the "MVP" uniform
    // For each model you render, since the MVP will be different (at least the M part)
    glUniformMatrix4fv(self.characterMvpUniformIdx, 1, GL_FALSE, &MVP[0][0]);
	
    // Bind the texture to be used
	glBindTexture(GL_TEXTURE_2D, self.characterTexName);
    
	// Bind our vertex array object
	glBindVertexArray(self.characterVAOName);
    
    glDrawElements(GL_TRIANGLES, assElements.size(), GL_UNSIGNED_SHORT, 0);
    
    self.characterAngle++;
}

static GLsizei GetGLTypeSize(GLenum type)
{
	switch (type) {
		case GL_BYTE:
			return sizeof(GLbyte);
		case GL_UNSIGNED_BYTE:
			return sizeof(GLubyte);
		case GL_SHORT:
			return sizeof(GLshort);
		case GL_UNSIGNED_SHORT:
			return sizeof(GLushort);
		case GL_INT:
			return sizeof(GLint);
		case GL_UNSIGNED_INT:
			return sizeof(GLuint);
		case GL_FLOAT:
			return sizeof(GLfloat);
	}
	return 0;
}

- (GLuint) buildVAO
{
	GLuint vaoName;
	
	// Create a vertex array object (VAO) to cache model parameters
	glGenVertexArrays(1, &vaoName);
	glBindVertexArray(vaoName);
    
    GLuint posBufferName;
    
    // Create a vertex buffer object (VBO) to store positions
    glGenBuffers(1, &posBufferName);
    glBindBuffer(GL_ARRAY_BUFFER, posBufferName);
    
    // Allocate and load position data into the VBO
    glBufferData(GL_ARRAY_BUFFER, assPositions.size() * sizeof(glm::vec3), &assPositions[0], GL_STATIC_DRAW);
    
    // Enable the position attribute for this VAO
    glEnableVertexAttribArray(POS_ATTRIB_IDX);
    
    // Get the size of the position type so we can set the stride properly
    //GLsizei posTypeSize = GetGLTypeSize(GL_FLOAT);
    
    // Set up parmeters for position attribute in the VAO including,
    //  size, type, stride, and offset in the currenly bound VAO
    // This also attaches the position VBO to the VAO
    glVertexAttribPointer(POS_ATTRIB_IDX,		// What attibute index will this array feed in the vertex shader (see buildProgram)
                          3,	// How many elements are there per position?
                          GL_FLOAT,	// What is the type of this data?
                          GL_FALSE,				// Do we want to normalize this data (0-1 range for fixed-pont types)
                          0, // What is the stride (i.e. bytes between positions)?
                          BUFFER_OFFSET(0));	// What is the offset in the VBO to the position data?
    
    GLuint texcoordBufferName;
    
    // Create a vertex buffer object (VBO) to store positions
    glGenBuffers(1, &texcoordBufferName);
    glBindBuffer(GL_ARRAY_BUFFER, texcoordBufferName);
    
    // Allocate and load color data into the VBO
    glBufferData(GL_ARRAY_BUFFER, assTexcoords.size() * sizeof(glm::vec2), &assTexcoords[0], GL_STATIC_DRAW);
    
    // Enable the position attribute for this VAO
    glEnableVertexAttribArray(TEXCOORD_ATTRIB_IDX);
    
    // Get the size of the position type so we can set the stride properly
    //GLsizei posTypeSize = GetGLTypeSize(GL_FLOAT);
    
    // Set up parmeters for position attribute in the VAO including,
    //  size, type, stride, and offset in the currenly bound VAO
    // This also attaches the position VBO to the VAO
    glVertexAttribPointer(TEXCOORD_ATTRIB_IDX,		// What attibute index will this array feed in the vertex shader (see buildProgram)
                          2,	// How many elements are there per position?
                          GL_FLOAT,	// What is the type of this data?
                          GL_FALSE,				// Do we want to normalize this data (0-1 range for fixed-pont types)
                          0, // What is the stride (i.e. bytes between positions)?
                          BUFFER_OFFSET(0));	// What is the offset in the VBO to the position data?
    
    GLuint elementBufferName;
    
    // Create a VBO to vertex array elements
    // This also attaches the element array buffer to the VAO
    glGenBuffers(1, &elementBufferName);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, elementBufferName);
    
    // Allocate and load vertex array element data into VBO
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, assElements.size() * sizeof(unsigned short), &assElements[0] , GL_STATIC_DRAW);

	GetGLError();
	
	return vaoName;
}

-(void)destroyVAO:(GLuint) vaoName
{
     GLuint index;
     GLuint bufName;
     
     // Bind the VAO so we can get data from it
     glBindVertexArray(vaoName);
     
     // For every possible attribute set in the VAO
     for(index = 0; index < 16; index++)
     {
         // Get the VBO set for that attibute
         glGetVertexAttribiv(index , GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, (GLint*)&bufName);
     
         // If there was a VBO set...
         if(bufName)
         {
             //...delete the VBO
             glDeleteBuffers(1, &bufName);
         }
     }
     
     // Get any element array VBO set in the VAO
     glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, (GLint*)&bufName);
     
     // If there was a element array VBO set in the VAO
     if(bufName)
     {
         //...delete the VBO
         glDeleteBuffers(1, &bufName);
     }
     
     // Finally, delete the VAO
     glDeleteVertexArrays(1, &vaoName);
     
     GetGLError();
}

-(GLuint) buildTexture:(demoImage*) image
{
	GLuint texName;
	
	// Create a texture object to apply to model
	glGenTextures(1, &texName);
	glBindTexture(GL_TEXTURE_2D, texName);
	
	// Set up filter and wrap modes for this texture object
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
	
	// Indicate that pixel rows are tightly packed
	//  (defaults to stride of 4 which is kind of only good for
	//  RGBA or FLOAT data types)
	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	
	// Allocate and load image data into texture
	glTexImage2D(GL_TEXTURE_2D, 0, image->format, image->width, image->height, 0,
				 image->format, image->type, image->data);
    
	// Create mipmaps for this texture for better image quality
	glGenerateMipmap(GL_TEXTURE_2D);
	
	GetGLError();
	
	return texName;
}

-(GLuint) buildProgramWithVertexSource:(demoSource*)vertexSource
					withFragmentSource:(demoSource*)fragmentSource
{
	GLuint prgName;
	
	GLint logLength, status;
	
	// String to pass to glShaderSource
	GLchar* sourceString = NULL;
	
	// Determine if GLSL version 140 is supported by this context.
	//  We'll use this info to generate a GLSL shader source string
	//  with the proper version preprocessor string prepended
	float  glLanguageVersion;
	
#if ESSENTIAL_GL_PRACTICES_IOS
	sscanf((char *)glGetString(GL_SHADING_LANGUAGE_VERSION), "OpenGL ES GLSL ES %f", &glLanguageVersion);
#else
	sscanf((char *)glGetString(GL_SHADING_LANGUAGE_VERSION), "%f", &glLanguageVersion);
#endif
	
	// GL_SHADING_LANGUAGE_VERSION returns the version standard version form
	//  with decimals, but the GLSL version preprocessor directive simply
	//  uses integers (thus 1.10 should 110 and 1.40 should be 140, etc.)
	//  We multiply the floating point number by 100 to get a proper
	//  number for the GLSL preprocessor directive
	GLuint version = 100 * glLanguageVersion;
	
	// Get the size of the version preprocessor string info so we know
	//  how much memory to allocate for our sourceString
	const GLsizei versionStringSize = sizeof("#version 123\n");
	
	// Create a program object
	prgName = glCreateProgram();
	
	// Indicate the attribute indicies on which vertex arrays will be
	//  set with glVertexAttribPointer
	//  See buildVAO to see where vertex arrays are actually set
	glBindAttribLocation(prgName, POS_ATTRIB_IDX, "inPosition");
    
    glBindAttribLocation(prgName, TEXCOORD_ATTRIB_IDX, "inTexcoord");
	
	//////////////////////////////////////
	// Specify and compile VertexShader //
	//////////////////////////////////////
	
	// Allocate memory for the source string including the version preprocessor information
	sourceString = (char *)malloc(vertexSource->byteSize + versionStringSize);
	
	// Prepend our vertex shader source string with the supported GLSL version so
	//  the shader will work on ES, Legacy, and OpenGL 3.2 Core Profile contexts
	sprintf(sourceString, "#version %d\n%s", version, vertexSource->string);
    
	GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
	glShaderSource(vertexShader, 1, (const GLchar **)&(sourceString), NULL);
	glCompileShader(vertexShader);
	glGetShaderiv(vertexShader, GL_INFO_LOG_LENGTH, &logLength);
	
	if (logLength > 0)
	{
		GLchar *log = (GLchar*) malloc(logLength);
		glGetShaderInfoLog(vertexShader, logLength, &logLength, log);
		NSLog(@"Vtx Shader compile log:%s\n", log);
		free(log);
	}
	
	glGetShaderiv(vertexShader, GL_COMPILE_STATUS, &status);
	if (status == 0)
	{
		NSLog(@"Failed to compile vtx shader:\n%s\n", sourceString);
		return 0;
	}
	
	free(sourceString);
	sourceString = NULL;
	
	// Attach the vertex shader to our program
	glAttachShader(prgName, vertexShader);
	
	// Delete the vertex shader since it is now attached
	// to the program, which will retain a reference to it
	glDeleteShader(vertexShader);
	
	/////////////////////////////////////////
	// Specify and compile Fragment Shader //
	/////////////////////////////////////////
	
	// Allocate memory for the source string including the version preprocessor	 information
	sourceString = (char *)malloc(fragmentSource->byteSize + versionStringSize);
	
	// Prepend our fragment shader source string with the supported GLSL version so
	//  the shader will work on ES, Legacy, and OpenGL 3.2 Core Profile contexts
	sprintf(sourceString, "#version %d\n%s", version, fragmentSource->string);
	
	GLuint fragShader = glCreateShader(GL_FRAGMENT_SHADER);
	glShaderSource(fragShader, 1, (const GLchar **)&(sourceString), NULL);
	glCompileShader(fragShader);
	glGetShaderiv(fragShader, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0)
	{
		GLchar *log = (GLchar*)malloc(logLength);
		glGetShaderInfoLog(fragShader, logLength, &logLength, log);
		NSLog(@"Frag Shader compile log:\n%s\n", log);
		free(log);
	}
	
	glGetShaderiv(fragShader, GL_COMPILE_STATUS, &status);
	if (status == 0)
	{
		NSLog(@"Failed to compile frag shader:\n%s\n", sourceString);
		return 0;
	}
	
	free(sourceString);
	sourceString = NULL;
	
	// Attach the fragment shader to our program
	glAttachShader(prgName, fragShader);
	
	// Delete the fragment shader since it is now attached
	// to the program, which will retain a reference to it
	glDeleteShader(fragShader);
	
	//////////////////////
	// Link the program //
	//////////////////////
	
	glLinkProgram(prgName);
	glGetProgramiv(prgName, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0)
	{
		GLchar *log = (GLchar*)malloc(logLength);
		glGetProgramInfoLog(prgName, logLength, &logLength, log);
		NSLog(@"Program link log:\n%s\n", log);
		free(log);
	}
	
	glGetProgramiv(prgName, GL_LINK_STATUS, &status);
	if (status == 0)
	{
		NSLog(@"Failed to link program");
		return 0;
	}
	
	glValidateProgram(prgName);
	glGetProgramiv(prgName, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0)
	{
		GLchar *log = (GLchar*)malloc(logLength);
		glGetProgramInfoLog(prgName, logLength, &logLength, log);
		NSLog(@"Program validate log:\n%s\n", log);
		free(log);
	}
	
	glGetProgramiv(prgName, GL_VALIDATE_STATUS, &status);
	if (status == 0)
	{
		NSLog(@"Failed to validate program");
		return 0;
	}
	
	
	glUseProgram(prgName);
	
	///////////////////////////////////////
	// Setup common program input points //
	///////////////////////////////////////
    
	
	GLint samplerLoc = glGetUniformLocation(prgName, "diffuseTexture");
	
	// Indicate that the diffuse texture will be bound to texture unit 0
	GLint unit = 0;
	glUniform1i(samplerLoc, unit);
	
	GetGLError();
	
	return prgName;
	
}

- (id) initWithDefaultFBO: (GLuint) defaultFBOName
{
	if((self = [super init]))
	{
		NSLog(@"%s %s", glGetString(GL_RENDERER), glGetString(GL_VERSION));
        
        ////////////////////////////////////////////////////
		// Build all of our and setup initial state here  //
		// Don't wait until our real time run loop begins //
		////////////////////////////////////////////////////
		
		self.defaultFBOName = defaultFBOName;
		
		self.viewWidth = 100;
		self.viewHeight = 100;
        
        self.characterAngle = 0;
		
		self.useVBOs = USE_VERTEX_BUFFER_OBJECTS;
        
        NSString* filePathName = nil;
        
        //////////////////////////////
		// Load our character model //
		//////////////////////////////
        
        filePathName = [[NSBundle mainBundle] pathForResource:@"cube" ofType:@"obj"];
        const char * path = [filePathName cStringUsingEncoding:NSASCIIStringEncoding];
        
        // Read our .obj file
        bool res = loadAssImp(path, assElements, assPositions, assTexcoords, assNormals);
        if(!res)
		{
			NSLog(@"Could not load obj file");
		}
        
        // Build Vertex Buffer Objects (VBOs) and Vertex Array Object (VAOs) with our model data
		self.characterVAOName = [self buildVAO];
        
        ////////////////////////////////////
		// Load texture for our character //
		////////////////////////////////////
		
		filePathName = [[NSBundle mainBundle] pathForResource:@"uvtemplate" ofType:@"bmp"];
		demoImage *image = imgLoadImage([filePathName cStringUsingEncoding:NSASCIIStringEncoding], false);
		
		// Build a texture object with our image data
		self.characterTexName = [self buildTexture:image];
		
		// We can destroy the image once it's loaded into GL
		imgDestroyImage(image);
		
		////////////////////////////////////////////////////
		// Load and Setup shaders for character rendering //
		////////////////////////////////////////////////////
		
		demoSource *vtxSource = NULL;
		demoSource *frgSource = NULL;
		
		filePathName = [[NSBundle mainBundle] pathForResource:@"texture1" ofType:@"vsh"];
		vtxSource = srcLoadSource([filePathName cStringUsingEncoding:NSASCIIStringEncoding]);
		
		filePathName = [[NSBundle mainBundle] pathForResource:@"texture1" ofType:@"fsh"];
		frgSource = srcLoadSource([filePathName cStringUsingEncoding:NSASCIIStringEncoding]);
		
		// Build Program
		self.characterPrgName = [self buildProgramWithVertexSource:vtxSource
                                                withFragmentSource:frgSource];
		
		srcDestroySource(vtxSource);
		srcDestroySource(frgSource);
		
		self.characterMvpUniformIdx = glGetUniformLocation(self.characterPrgName, "modelViewProjectionMatrix");
		
		if(self.characterMvpUniformIdx < 0)
		{
			NSLog(@"No modelViewProjectionMatrix in character shader");
		}

        ////////////////////////////////////////////////
		// Set up OpenGL state that will never change //
		////////////////////////////////////////////////
		
		// Depth test will always be enabled
		glEnable(GL_DEPTH_TEST);
        
		// We will always cull back faces for better performance
		glEnable(GL_CULL_FACE);
		
		// Always use this clear color
		glClearColor(0.0f, 0.0f, 0.4f, 0.0f);
		
		// Draw our scene once without presenting the rendered image.
		//   This is done in order to pre-warm OpenGL
		// We don't need to present the buffer since we don't actually want the 
		//   user to see this, we're only drawing as a pre-warm stage
		[self render];
		
		// Check for errors to make sure all of our setup went ok
		GetGLError();
	}
	
	return self;
}


- (void) dealloc
{
    // Cleanup all OpenGL objects and
	glDeleteTextures(1, &_characterTexName);
    
	[self destroyVAO:_characterVAOName];
    
	glDeleteProgram(_characterPrgName);
	
    [super dealloc];
}

@end
